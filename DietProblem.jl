
using JuMP
using GLPKMathProgInterface

Pkg.add("DataDeps")




Pkg.add("ExcelFiles")


Pkg.add("DataFrames")

using DataDeps

register(DataDep(
    "AUSNUT Food Nutrient Database",
    """
        Website: http://www.foodstandards.gov.au/science/monitoringnutrients/
        Excel spreedsheet of food nutrient values prepared by Food Standard Australia New Zealand, between 2011 and 2013.
    """,
    "http://www.foodstandards.gov.au/science/monitoringnutrients/ausnut/Documents/8b.%20AUSNUT%202011-13%20AHS%20Food%20Nutrient%20Database.xls",
     "4bac90de8ab2673a2f9b19f0be4c822aac1832ed8314117666e5464ed57cb544"
        ;
    post_fetch_method = (fn)->mv(fn, "database.xls")
));




using ExcelFiles, DataFrames

const nutrients = DataFrame(load("ausnut.xls", "Food Nutrient Database"))
nutrients[1:4,:]



#nutrients[:, Symbol("Protein (g)")] 

#nutrients[1, Symbol("Protein (g)")]



using JuMP
using LinearAlgebra
function new_diet(solver = GLPKSolverLP())
    m = Model(solver= solver)
    @variable(m, diet[1:size(nutrients,1)], lowerbound=0)
    m, diet 
end



function total_intake(nutrient_name, diet)
    nutrients[:, Symbol(nutrient_name)] ⋅ diet
end

function basic_nutrient_requirements(m::Model, diet, weight = 62) # average human is 62 kg
    intake(nutrient_name) = total_intake(nutrient_name, diet) 
    # ^ closure over the diet given as an argument
        
    @constraints(m, begin
        70 <= intake("Protein (g)") 
        70 <= intake("Total fat (g)") 
        24 <= intake("Total saturated fat (g)") 
        90 <= intake("Total sugars (g)") 
        intake("Alcohol (g)") <= 100
        310 <= intake("Available carbohydrates, with sugar alcohols (g)") 
        intake("Sodium (Na) (mg)") <= 2300 # Heart Council
        intake("Caffeine (mg)") <= 400
        25 <=intake("Dietary fibre (g)") 
        24 <= intake("Total trans fatty acids (mg)") 
        25 <= intake("Vitamin A retinol equivalents (µg)") <= 900
        1.2 <= intake("Thiamin (B1) (mg)") 
        400 <= intake("Dietary folate equivalents  (µg)") 
        1000 <= intake("Folic acid  (µg)") # https://ods.od.nih.gov/factsheets/Folate-HealthProfessional/
        75 <= intake("Vitamin C (mg)") <= 2000 ##https://en.wikipedia.org/wiki/Dietary_Reference_Intake
        95 <= intake("Iodine (I) (µg)") <=1100 ##https://en.wikipedia.org/wiki/Dietary_Reference_Intake
        6 <= intake("Iron (Fe) (mg)") <= 45 # #https://en.wikipedia.org/wiki/Dietary_Reference_Intake
        330 <= intake("Magnesium (Mg) (mg)") 
        580 <= intake("Phosphorus (P) (mg)") <= 4000 #https://en.wikipedia.org/wiki/Dietary_Reference_Intake
        4700 <= intake("Potassium (K) (mg)") 
        800 <= intake("Calcium (Ca) (mg)") <= 2500 #https://en.wikipedia.org/wiki/Dietary_Reference_Intake
        3.5*weight <= intake("Tryptophan (mg)") <= 0.5*weight*1600 #0.5 * LD50 https://books.google.com.au/books?id=he7LBQAAQBAJ&pg=PA210&lpg=PA210&dq=Tryptophan+LD-50&source=bl&ots=yzi5Hx7hM2&sig=sd78LGAnavIwtT5AP-L4fzsFLZM&hl=en&sa=X&ved=0ahUKEwjJhcjFn6rQAhUKkJQKHbw6AiwQ6AEIMTAE#v=onepage&q=Tryptophan%20LD-50&f=false
                                                #http://www.livestrong.com/article/541961-how-much-tryptophan-per-day/
        17 <= intake("Linoleic acid (g)") 

        45 <= intake("Selenium (Se) (µg)") <= 400 #https://en.wikipedia.org/wiki/Dietary_Reference_Intake
        11 <= intake("Zinc (Zn) (mg)") <= 40 #https://en.wikipedia.org/wiki/Dietary_Reference_Intake
            
            
        6 <= intake("Vitamin E (mg)") <= 1_200    #https://www.livestrong.com/article/465706-vitamin-e-overdose-levels/
            
        1.3 <= intake("Vitamin B6 (mg)") <= 300  #https://www.news-medical.net/health/Can-You-Take-Too-Much-Vitamin-B.aspx
        2.4 <= intake("Vitamin B12  (µg)")   #https://www.news-medical.net/health/Can-You-Take-Too-Much-Vitamin-B.aspx
            
    end)
    
end





filter(x->occursin(x, "Vitamin B"), String.(collect(names(nutrients))))



function show_diet(diet)
    for ii in eachindex(diet)
        amount = getvalue(diet[ii])
        if amount > 0
            name = nutrients[ii, Symbol("Food Name")]
            grams = round(Int, 100amount) # amount is expressed in units of 100 grams
            display_as = grams < 1  ? ">0" : string(grams) #Make things that are "0.001 grams" show as ">0 grams"
            println(lpad(display_as, 5, " "), " grams \t", name)
        end
    end
end





m, diet = new_diet()
basic_nutrient_requirements(m, diet);

@constraint(m, diet .<= 5) # nothing more than 500g
@constraint(m, total_intake("Moisture (g)", diet) <= 0.25sum(diet)*100) # Less than 25% liquid

@objective(m, Min,  
    total_intake("Energy, with dietary fibre (kJ)", diet) + 0.01sum(diet)
)
@show status = solve(m)
show_diet(diet)



using DelimitedFiles

function forbid_liquids(m::Model, diet, keywords=["milk", "drink", "Water", "Milk"])
    # not blocking lowercase "water" as that would block "Soup made with water"
    
    inds = keyword_using_inds = findall(x->any(occursin.(x, keywords)), nutrients[:, Symbol("Food Name")])
    high_moisture_inds =  findall(x->x>50, nutrients[:, Symbol("Moisture (g)")])
    inds = intersect(keyword_using_inds, high_moisture_inds)
    #@show nutrients[inds, Symbol("Food Name")]
    @constraint(m, diet[inds] .== 0 ) # nothing more than 500g

end





m, diet = new_diet()
basic_nutrient_requirements(m, diet);
forbid_liquids(m, diet)

@constraint(m, diet .<= 3) # nothing more than 300g

@objective(m, Min,  
    total_intake("Energy, with dietary fibre (kJ)", diet) + 0.01sum(diet)
)
@show status = solve(m)
show_diet(diet)



#based on articles from https://www.nal.usda.gov/fnic/dri-tables-and-application-reports
#recommendation for man 19-30 years old
function endurance_athlete_requirements(m::Model, diet, weight = 70) # his weight is 70 kg
    intake(nutrient_name) = total_intake(nutrient_name, diet) 
    # ^ closure over the diet given as an argument
        
    @constraints(m, begin
        91 <= intake("Protein (g)") 
        70 <= intake("Total fat (g)") 
        24 <= intake("Total saturated fat (g)") 
        70 <= intake("Total sugars (g)") 
        intake("Alcohol (g)") <= 0
        350 <= intake("Available carbohydrates, with sugar alcohols (g)") 
        intake("Sodium (Na) (mg)") <= 2300 # Heart Council
        intake("Caffeine (mg)") <= 400
        25 <=intake("Dietary fibre (g)") 
        24 <= intake("Total trans fatty acids (mg)") 
        900 <= intake("Vitamin A retinol equivalents (µg)") <= 3000
        1.2 <= intake("Thiamin (B1) (mg)") 
        400 <= intake("Dietary folate equivalents  (µg)") 
        1000 <= intake("Folic acid  (µg)") # https://ods.od.nih.gov/factsheets/Folate-HealthProfessional/
        75 <= intake("Vitamin C (mg)") <= 2000 ##https://en.wikipedia.org/wiki/Dietary_Reference_Intake
        #600 <= intake("Vitamin D (IU)") <= 4000
        95 <= intake("Iodine (I) (µg)") <=1100 ##https://en.wikipedia.org/wiki/Dietary_Reference_Intake
        6 <= intake("Iron (Fe) (mg)") <= 45 # #https://en.wikipedia.org/wiki/Dietary_Reference_Intake
        330 <= intake("Magnesium (Mg) (mg)") 
        580 <= intake("Phosphorus (P) (mg)") <= 4000 #https://en.wikipedia.org/wiki/Dietary_Reference_Intake
        4700 <= intake("Potassium (K) (mg)") 
        800 <= intake("Calcium (Ca) (mg)") <= 2500 #https://en.wikipedia.org/wiki/Dietary_Reference_Intake
        3.5*weight <= intake("Tryptophan (mg)") <= 0.5*weight*1600 #0.5 * LD50 https://books.google.com.au/books?id=he7LBQAAQBAJ&pg=PA210&lpg=PA210&dq=Tryptophan+LD-50&source=bl&ots=yzi5Hx7hM2&sig=sd78LGAnavIwtT5AP-L4fzsFLZM&hl=en&sa=X&ved=0ahUKEwjJhcjFn6rQAhUKkJQKHbw6AiwQ6AEIMTAE#v=onepage&q=Tryptophan%20LD-50&f=false
                                                #http://www.livestrong.com/article/541961-how-much-tryptophan-per-day/
        17 <= intake("Linoleic acid (g)")
        #550 <= intake("Choline (g)")
        #16 <= intake("Niacin (g)")
        #5 <= intake("Patothenic Acid (mg)")
        
        45 <= intake("Selenium (Se) (µg)") <= 400 #https://en.wikipedia.org/wiki/Dietary_Reference_Intake
        11 <= intake("Zinc (Zn) (mg)") <= 40 #https://en.wikipedia.org/wiki/Dietary_Reference_Intake
            
            
        15 <= intake("Vitamin E (mg)") <= 1000    #https://www.livestrong.com/article/465706-vitamin-e-overdose-levels/
        #120 <= intake("Vitamin K (µg)") 
            
        1.3 <= intake("Vitamin B6 (mg)") <= 100  #https://www.news-medical.net/health/Can-You-Take-Too-Much-Vitamin-B.aspx
        2.4 <= intake("Vitamin B12  (µg)")   #https://www.news-medical.net/health/Can-You-Take-Too-Much-Vitamin-B.aspx
        #1.3 <= intake("Vitamin B2 (mg)")
        
    end)
    
end







m, diet = new_diet()
endurance_athlete_requirements(m, diet);
forbid_liquids(m, diet)
@constraint(m, diet .<= 3) # nothing more than 300g


@constraint(m,
    9_000 <=
        total_intake("Energy, with dietary fibre (kJ)", diet)
    <= 12_000
    )
@objective(m, Max,  
    total_intake("Protein (g)", diet)
)
@show status = solve(m)
show_diet(diet)



function total_intake(nutrient_name, diet)
    nutrients[:, Symbol(nutrient_name)] ⋅ diet
end

function basic_nutrient_group(m::Model, diet, weight = 62) # average human is 62 kg
    intake(nutrient_name) = total_intake(nutrient_name, diet) 
    # ^ closure over the diet given as an argument
        
    @constraints(m, begin
        70 <= intake("Protein (g)") 
        70 <= intake("Total fat (g)") 
        24 <= intake("Total saturated fat (g)") 
        90 <= intake("Total sugars (g)") 
        intake("Alcohol (g)") <= 100
        310 <= intake("Available carbohydrates, with sugar alcohols (g)") 
        intake("Sodium (Na) (mg)") <= 2300 # Heart Council
        intake("Caffeine (mg)") <= 400
        25 <=intake("Dietary fibre (g)") 
        24 <= intake("Total trans fatty acids (mg)") 
        25 <= intake("Vitamin A retinol equivalents (µg)") <= 900
        1.2 <= intake("Thiamin (B1) (mg)") 
        400 <= intake("Dietary folate equivalents  (µg)") 
        1000 <= intake("Folic acid  (µg)") # https://ods.od.nih.gov/factsheets/Folate-HealthProfessional/
        75 <= intake("Vitamin C (mg)") <= 2000 ##https://en.wikipedia.org/wiki/Dietary_Reference_Intake
        95 <= intake("Iodine (I) (µg)") <=1100 ##https://en.wikipedia.org/wiki/Dietary_Reference_Intake
        6 <= intake("Iron (Fe) (mg)") <= 45 # #https://en.wikipedia.org/wiki/Dietary_Reference_Intake
        330 <= intake("Magnesium (Mg) (mg)") 
        580 <= intake("Phosphorus (P) (mg)") <= 4000 #https://en.wikipedia.org/wiki/Dietary_Reference_Intake
        4700 <= intake("Potassium (K) (mg)") 
        800 <= intake("Calcium (Ca) (mg)") <= 2500 #https://en.wikipedia.org/wiki/Dietary_Reference_Intake
        3.5*weight <= intake("Tryptophan (mg)") <= 0.5*weight*1600 #0.5 * LD50 https://books.google.com.au/books?id=he7LBQAAQBAJ&pg=PA210&lpg=PA210&dq=Tryptophan+LD-50&source=bl&ots=yzi5Hx7hM2&sig=sd78LGAnavIwtT5AP-L4fzsFLZM&hl=en&sa=X&ved=0ahUKEwjJhcjFn6rQAhUKkJQKHbw6AiwQ6AEIMTAE#v=onepage&q=Tryptophan%20LD-50&f=false
                                                #http://www.livestrong.com/article/541961-how-much-tryptophan-per-day/
        17 <= intake("Linoleic acid (g)") 

        45 <= intake("Selenium (Se) (µg)") <= 400 #https://en.wikipedia.org/wiki/Dietary_Reference_Intake
        11 <= intake("Zinc (Zn) (mg)") <= 40 #https://en.wikipedia.org/wiki/Dietary_Reference_Intake
            
            
        6 <= intake("Vitamin E (mg)") <= 1_200    #https://www.livestrong.com/article/465706-vitamin-e-overdose-levels/
            
        1.3 <= intake("Vitamin B6 (mg)") <= 300  #https://www.news-medical.net/health/Can-You-Take-Too-Much-Vitamin-B.aspx
        2.4 <= intake("Vitamin B12  (µg)")   #https://www.news-medical.net/health/Can-You-Take-Too-Much-Vitamin-B.aspx
            
    end)
    
end





m, diet = new_diet()
basic_nutrient_group(m, diet);
forbid_liquids(m, diet)

@constraint(m, diet .<= 5) # nothing more than 500g
@constraint(m, total_intake("Moisture (g)", diet) <= 0.25sum(diet)*100) # Less than 25% liquid

# @objective(m, Min,  
#      total_intake("Energy, with dietary fibre (kJ)", diet) + 0.01sum(diet)
#  )
@objective(m, Min, sum(diet))
@show status = solve(m)
show_diet(diet*20)

println("Total: $(round(Int, 100sum(getvalue(diet)))) grams")


