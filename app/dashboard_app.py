from flask import Flask, render_template, url_for, request
from flask_mysqldb import MySQL
from flask_basicauth import BasicAuth

import datetime
import csv

def init_database(app):
   with app.app_context():
      cursor = mysql.connection.cursor()
      cursor.execute('''
          create table if not exists dashboard (
              id int not null auto_increment primary key,
              center varchar(20),
              resources int,
              tasks int,
              date date,
              productivity float,
              constraint uc_country_date unique (center,date)
              )   
      ''')
      # load sample data
      csv_data = csv.reader(open('static/sampledata.csv'))
      cursor = mysql.connection.cursor()
      for row in csv_data:
            cursor.execute("insert into dashboard (id,center,resources,tasks,date,productivity) values (%s, %s, %s, %s, %s, %s) as new on duplicate key update center = new.center, resources = new.resources, tasks = new.tasks, date = new.date, productivity = new.productivity", row)
      mysql.connection.commit()
      cursor.close()

def create_app():
    global mysql
    app = Flask(__name__)
    app.config.from_pyfile("config.py")
    mysql = MySQL(app)
    init_database(app)
    return app


app = create_app()

basic_auth = BasicAuth(app)

# configuration values
app.config['COUNTRIES'] = ['SPA', 'UK', 'FRA']

app.config['DAYS_PER_WEEK'] = 5
app.config['SPA_HOURS_DAY'] = 7.5
app.config['SPA_ANNUAL_LEAVE'] = 25
app.config['SPA_PUBLIC_HOLIDAYS'] = 12
app.config['FRA_HOURS_DAY'] = 7
app.config['FRA_ANNUAL_LEAVE'] = 30
app.config['FRA_PUBLIC_HOLIDAYS'] = 12
app.config['UK_HOURS_DAY'] = 8
app.config['UK_ANNUAL_LEAVE'] = 20
app.config['UK_PUBLIC_HOLIDAYS'] = 12

app.config['SPA_RESOURCES_DEFAULT'] = 9
app.config['SPA_TASKS_DEFAULT'] = 9
app.config['FRA_RESOURCES_DEFAULT'] = 10
app.config['FRA_TASKS_DEFAULT'] = 10
app.config['UK_RESOURCES_DEFAULT'] = 8
app.config['UK_TASKS_DEFAULT'] = 8

app.config['GENERATION_PRODUCTIVITY_START_DATE'] = datetime.date(2023,11,1)


# calculates productivity through 3 variables
def calc_productivity(country, resources, task_resolved):

    hours_per_day = app.config[country+'_HOURS_DAY']
    annual_leave = app.config[country+'_ANNUAL_LEAVE']
    public_holidays = app.config[country+'_PUBLIC_HOLIDAYS']

    week_working_hours = app.config['DAYS_PER_WEEK'] * hours_per_day
    total_holidays = annual_leave + public_holidays
    holidays_per_week = total_holidays / 52
    effective_days_per_week = app.config['DAYS_PER_WEEK'] - holidays_per_week
    effective_hours_per_week = effective_days_per_week * hours_per_day
    total_working_hours = float(resources) * effective_hours_per_week
    average_resources = total_working_hours / week_working_hours
    productivity = float(task_resolved) / average_resources

    # productivity equals to tasks resolved by one resource
    return productivity

# fetch all data available from a country ordered by date
def fetch_data_bycountry(country):
    cursor = mysql.connection.cursor()
    cursor.execute("SELECT center,resources,tasks,date,productivity from dashboard where center=%s order by date", (country,))
    all = cursor.fetchall()
    cursor.close()
    return all

# fetch all productivity values available from a country ordered by date
def fetch_productivity_bycountry(country):
    cursor = mysql.connection.cursor()
    cursor.execute("SELECT productivity from dashboard where center=%s order by date", (country,))
    all = cursor.fetchall()
    cursor.close()
    #we get an array of arrays, so we transform it into an array
    result = [row[0] for row in all]
    return result

# creates a list of dates in an array: from the configuration day until today (including today), format is datetime.date(200x, x, x)
def make_date_list():
    base = app.config['GENERATION_PRODUCTIVITY_START_DATE'] 
    today = datetime.date.today()
    num_of_days = (today - base).days
    num_of_days = num_of_days + 1
    date_list = [base + datetime.timedelta(days=x) for x in range(0,num_of_days)]
    return date_list

# solve problem of graphic misrepresentation when you want to see more than 1 country in the graphic and there is no data available in x dates
def generate_productivity_by_country(country):
    cursor = mysql.connection.cursor()
    cursor.execute("SELECT date,productivity from dashboard where center=%s order by date", (country,))
    all = cursor.fetchall()
    cursor.close()
    date_times_stored = [row[0] for row in all]
    #productivity_stored = [row[1] for row in all] 
    
    date_list = make_date_list()

    values_list = []

    for day_list in date_list:
        if day_list in date_times_stored:
            print('I am in the list')
            # append productivity values from query in values_list
            for item in all:
                date_time_stored, productivity_stored_linked = item
                if day_list == date_time_stored:
                    values_list.append(productivity_stored_linked)
        else:
            # date where productivity was not saved in db, then productivity is filled up by default with the default of resources and tasks (in the future maybe get true data of tasks)
            productivity = calc_productivity(country, app.config[country+'_RESOURCES_DEFAULT'], app.config[country+'_TASKS_DEFAULT'])
            values_list.append(productivity)
     
    return values_list

@app.route('/insert', methods=['GET', 'POST'])
def insert():
    print(url_for('insert'))
    if request.method == 'POST':

        # fetch data from the form
        country = request.form['country']
        resources = request.form['resources']
        tasks = request.form['tasks']
        date = request.form['date']

        # calculates productivity
        productivity = calc_productivity(country, resources, tasks)
        print(country, resources, tasks, date, productivity)

        # adds data to the db

        cursor = mysql.connection.cursor()
        try:
            cursor.execute("INSERT into dashboard (center, resources, tasks, date, productivity) VALUES (%s,%s,%s,%s,%s)", (country, resources, tasks, date, productivity))
            mysql.connection.commit()
            print(cursor.rowcount, "was inserted")
        except cursor.Error:
            print ('integrity error')
            return render_template('error.html')
        else:
            print('success')    
            cursor.close()
        
        #fetch data from a single country from db
        country_all_data = fetch_data_bycountry(country)
        print(country_all_data)

        # make a list of only the dates stored in db
        labels = [item[3] for item in country_all_data]
        labels = [date_obj.strftime("%m/%d/%Y") for date_obj in labels]

        # fetch only productivity values from a single country from db
        country_productivity = fetch_productivity_bycountry(country)
        print(country_productivity)

        # shows results
        return render_template('resultsbycountry.html', country_all_data=country_all_data, country_productivity=country_productivity, labels=labels, country=country)

    return render_template('insert.html', countries = app.config['COUNTRIES'])

# queries data available for a country without adding new data
@app.route('/query', methods=['GET', 'POST'])
def query():
    if request.method == 'POST':
        country = request.form['country']
        country_all_data = fetch_data_bycountry(country) 
        print(country_all_data)
        country_productivity = fetch_productivity_bycountry(country) 
        print(country_productivity)

        # make a list of only the dates stored in db
        labels = [item[3] for item in country_all_data]
        labels = [date_obj.strftime("%m/%d/%Y") for date_obj in labels]
        print(labels)
        return render_template ('resultsbycountry.html', country_all_data=country_all_data, country_productivity=country_productivity, labels=labels, country=country)
    return render_template('query.html', countries = app.config['COUNTRIES'])


# queries all data available in db without adding new data
@app.route('/')
def index():
    SPA_country_all_data = fetch_data_bycountry('SPA')
    FRA_country_all_data = fetch_data_bycountry('FRA') 
    UK_country_all_data = fetch_data_bycountry('UK') 

    SPA_country_productivity = generate_productivity_by_country('SPA')
    print(SPA_country_productivity)
    FRA_country_productivity = generate_productivity_by_country('FRA')
    print(FRA_country_productivity)
    UK_country_productivity = generate_productivity_by_country('UK')
    print(UK_country_productivity)

    labels = make_date_list()
    
    labels = [date_obj.strftime("%m/%d/%Y") for date_obj in labels]
    print(labels)
    #newlabel = []
    #for i in labels:
    #    t = i.strftime("%m/%d/%Y")
    #    newlabel.append(t)
    return render_template ('index.html', 
                            SPA_country_all_data=SPA_country_all_data, 
                            SPA_country_productivity=SPA_country_productivity,
                            FRA_country_all_data=FRA_country_all_data, 
                            FRA_country_productivity=FRA_country_productivity,
                            UK_country_all_data=UK_country_all_data, 
                            UK_country_productivity=UK_country_productivity, 
                            labels = labels)
