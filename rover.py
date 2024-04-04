# Import necessary modules
from flask import Flask, request, jsonify  
from flask_sqlalchemy import SQLAlchemy  
import heapq   
from math import radians, sin, cos, sqrt, atan2

# Create a Flask application instance
app = Flask(__name__)   

# Configure the Flask application to use SQLite database located at 'database.db'
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///database.db'

# Create an SQLAlchemy database instance
db = SQLAlchemy(app)    

# Define a database model for the 'User' table
class User(db.Model):    
    id = db.Column(db.Integer, primary_key=True)  
    username = db.Column(db.String(50), unique=True, nullable=False)  
    password = db.Column(db.String(100), nullable=False)  
    email = db.Column(db.String(100), unique=True, nullable=False)  
    events = db.relationship('EventSubscription', backref='user', lazy=True)
    pickups = db.relationship('PickupRequest', backref='user', lazy=True)

# Define a database model for the 'BusDriver' table
class BusDriver(db.Model):   # Define a class 'BusDriver' inheriting from db.Model
    # Define columns for the BusDriver table
    id = db.Column(db.Integer, primary_key=True)  # Define a column 'id' as primary key
    latitude = db.Column(db.Float, nullable=False)    # Define a column 'latitude' with float type and not nullable
    longitude = db.Column(db.Float, nullable=False)   # Define a column 'longitude' with float type and not nullable

# Define a database model for the 'Admin' table
class Admin(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(50), unique=True, nullable=False)
    password = db.Column(db.String(100), nullable=False)
    email = db.Column(db.String(100), unique=True, nullable=False)
    event_management_privilege = db.Column(db.Boolean, default=True)

# Define a database model for the 'Event' table
class Event(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), nullable=False)
    description = db.Column(db.Text)
    assigned_driver_id = db.Column(db.Integer, db.ForeignKey('bus_driver.id'))

    # Define a relationship with BusDriver table
    assigned_driver = db.relationship('BusDriver', backref='assigned_events')

# Define a database model for the 'EventSubscription' table
class EventSubscription(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    event_id = db.Column(db.Integer, db.ForeignKey('event.id'), nullable=False)

# Define a database model for the 'PickupRequest' table
class PickupRequest(db.Model):   
    id = db.Column(db.Integer, primary_key=True)  
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)  
    event_id = db.Column(db.Integer, db.ForeignKey('event.id'), nullable=False)
    latitude = db.Column(db.Float, nullable=False)    
    longitude = db.Column(db.Float, nullable=False)   

# Define a function to compute routes for the driver using Dijkstra's Algorithm
def compute_routes(driver_latitude, driver_longitude, users):
    graph = {}
    
    # Add driver's location to the graph
    graph['driver'] = {}
    for user in users:
        distance = calculate_distance(driver_latitude, driver_longitude, user.latitude, user.longitude)
        graph['driver'][user.id] = distance
    
    # Add users' locations to the graph
    for user in users:
        graph[user.id] = {}
        for other_user in users:
            if user.id != other_user.id:
                distance = calculate_distance(user.latitude, user.longitude, other_user.latitude, other_user.longitude)
                graph[user.id][other_user.id] = distance
    
    routes = {}
    for user in users:
        shortest_distance = dijkstra(graph, 'driver', user.id)
        routes[user.id] = shortest_distance
    
    return routes

# Define the route for user registration
@app.route('/api/users/register', methods=['POST'])
def register():
    # Retrieve JSON data from the request
    data = request.json   
    username = data.get('username')   
    password = data.get('password')   
    email = data.get('email')   

    # Validate user input
    if not username or not password or not email:
        return jsonify({'success': False, 'message': 'Please provide username, password, and email'}), 400

    # Check if username or email already exists in the database
    existing_user = User.query.filter((User.username == username) | (User.email == email)).first()
    if existing_user:
        return jsonify({'success': False, 'message': 'Username or email already exists'}), 409

    # Create a new User object
    new_user = User(username=username, password=password, email=email)
    
    # Add the new user to the database session
    db.session.add(new_user)
    
    try:
        # Commit the transaction to save the new user to the database
        db.session.commit()
        # Return a JSON response indicating successful registration
        return jsonify({'success': True, 'message': 'User registered successfully'}), 201
    except Exception as e:
        # Rollback the transaction in case of any error
        db.session.rollback()
        # Return a JSON response indicating registration failed
        return jsonify({'success': False, 'message': 'Failed to register user. Please try again later'}), 500

# Define the route for registering a new bus driver
@app.route('/api/drivers/register', methods=['POST'])
def register_driver():
    # Retrieve JSON data from the request
    data = request.json
    latitude = data.get('latitude')
    longitude = data.get('longitude')

    # Validate input
    if latitude is None or longitude is None:
        return jsonify({'success': False, 'message': 'Please provide latitude and longitude'}), 400

    # Create a new BusDriver object
    new_driver = BusDriver(latitude=latitude, longitude=longitude)

    # Add the new driver to the database session
    db.session.add(new_driver)

    try:
        # Commit the transaction to save the new driver to the database
        db.session.commit()
        # Return a JSON response indicating successful driver registration
        return jsonify({'success': True, 'message': 'Driver registered successfully'}), 201
    except Exception as e:
        # Rollback the transaction in case of any error
        db.session.rollback()
        # Return a JSON response indicating registration failed
        return jsonify({'success': False, 'message': 'Failed to register driver. Please try again later'}), 500

# Define the route for admin registration
@app.route('/api/admins/register', methods=['POST'])
def register_admin():
    # Retrieve JSON data from the request
    data = request.json
    username = data.get('username')
    password = data.get('password')

    # Validate input
    if not username or not password:
        return jsonify({'success': False, 'message': 'Please provide username and password'}), 400

    # Check if admin with the same username already exists
    existing_admin = Admin.query.filter_by(username=username).first()
    if existing_admin:
        return jsonify({'success': False, 'message': 'Username already exists'}), 409

    # Create a new Admin object
    new_admin = Admin(username=username, password=password)

    # Add the new admin to the database session
    db.session.add(new_admin)

    try:
        # Commit the transaction to save the new admin to the database
        db.session.commit()
        # Return a JSON response indicating successful admin registration
        return jsonify({'success': True, 'message': 'Admin registered successfully'}), 201
    except Exception as e:
        # Rollback the transaction in case of any error
        db.session.rollback()
        # Return a JSON response indicating registration failed
        return jsonify({'success': False, 'message': 'Failed to register admin. Please try again later'}), 500

# Define the route for user/driver/admin login
@app.route('/api/login', methods=['POST'])
def login():
    # Retrieve JSON data from the request
    data = request.json   
    username = data.get('username')   
    password = data.get('password')   

    # Check if the username and password are provided
    if not username or not password:
        return jsonify({'success': False, 'message': 'Please provide username and password'}), 400

    # Query User, BusDriver, and Admin tables to validate credentials
    user = User.query.filter_by(username=username, password=password).first()  
    driver = BusDriver.query.filter_by(username=username, password=password).first()  
    admin = Admin.query.filter_by(username=username, password=password).first()

    # Check if the credentials match any user, driver, or admin
    if user:
        return jsonify({'success': True, 'user_type': 'user', 'message': 'Login successful'}), 200
    elif driver:
        return jsonify({'success': True, 'user_type': 'driver', 'message': 'Login successful'}), 200
    elif admin:
        return jsonify({'success': True, 'user_type': 'admin', 'message': 'Login successful'}), 200
    else:
        return jsonify({'success': False, 'message': 'Invalid credentials'}), 401

# Define the route for updating user profile
@app.route('/api/user/<int:user_id>/update', methods=['PUT'])
def update_user(user_id):
    # Retrieve JSON data from the request
    data = request.json
    username = data.get('username')
    password = data.get('password')
    email = data.get('email')

    # Retrieve the user from the database
    user = User.query.get(user_id)
    if not user:
        return jsonify({'success': False, 'message': 'User not found'}), 404

    # Update user information
    if username:
        user.username = username
    if password:
        user.password = password
    if email:
        user.email = email

    try:
        # Commit the transaction to save the updated user profile
        db.session.commit()
        # Return a JSON response indicating successful profile update
        return jsonify({'success': True, 'message': 'User profile updated successfully'}), 200
    except Exception as e:
        # Rollback the transaction in case of any error
        db.session.rollback()
        # Return a JSON response indicating update failed
        return jsonify({'success': False, 'message': 'Failed to update user profile. Please try again later'}), 500

# Define the route for updating driver profile
@app.route('/api/driver/<int:driver_id>/update', methods=['PUT'])
def update_driver(driver_id):
    # Retrieve JSON data from the request
    data = request.json
    latitude = data.get('latitude')
    longitude = data.get('longitude')

    # Retrieve the driver from the database
    driver = BusDriver.query.get(driver_id)
    if not driver:
        return jsonify({'success': False, 'message': 'Driver not found'}), 404

    # Update driver information
    if latitude is not None:
        driver.latitude = latitude
    if longitude is not None:
        driver.longitude = longitude

    try:
        # Commit the transaction to save the updated driver profile
        db.session.commit()
        # Return a JSON response indicating successful profile update
        return jsonify({'success': True, 'message': 'Driver profile updated successfully'}), 200
    except Exception as e:
        # Rollback the transaction in case of any error
        db.session.rollback()
        # Return a JSON response indicating update failed
        return jsonify({'success': False, 'message': 'Failed to update driver profile. Please try again later'}), 500

# Define the route for updating admin profile
@app.route('/api/admin/<int:admin_id>/update', methods=['PUT'])
def update_admin(admin_id):
    # Retrieve JSON data from the request
    data = request.json
    username = data.get('username')
    password = data.get('password')
    email = data.get('email')

    # Retrieve the admin from the database
    admin = Admin.query.get(admin_id)
    if not admin:
        return jsonify({'success': False, 'message': 'Admin not found'}), 404

    # Update admin information
    if username:
        admin.username = username
    if password:
        admin.password = password
    if email:
        admin.email = email

    try:
        # Commit the transaction to save the updated admin profile
        db.session.commit()
        # Return a JSON response indicating successful profile update
        return jsonify({'success': True, 'message': 'Admin profile updated successfully'}), 200
    except Exception as e:
        # Rollback the transaction in case of any error
        db.session.rollback()
        # Return a JSON response indicating update failed
        return jsonify({'success': False, 'message': 'Failed to update admin profile. Please try again later'}), 500

# Define the route for creating a new event
@app.route('/api/event/create', methods=['POST'])
def create_event():
    # Retrieve JSON data from the request
    data = request.json
    name = data.get('name')
    description = data.get('description')

    # Validate input
    if not name:
        return jsonify({'success': False, 'message': 'Please provide a name for the event'}), 400

    # Create a new Event object
    new_event = Event(name=name, description=description)

    # Add the new event to the database session
    db.session.add(new_event)

    try:
        # Commit the transaction to save the new event to the database
        db.session.commit()
        # Return a JSON response indicating successful event creation
        return jsonify({'success': True, 'message': 'Event created successfully'}), 201
    except Exception as e:
        # Rollback the transaction in case of any error
        db.session.rollback()
        # Return a JSON response indicating event creation failed
        return jsonify({'success': False, 'message': 'Failed to create event. Please try again later'}), 500

# Define the route for getting event details
@app.route('/api/event/<int:event_id>/details', methods=['GET'])
def get_event_details(event_id):
    # Retrieve the event from the database
    event = Event.query.get(event_id)
    if not event:
        return jsonify({'success': False, 'message': 'Event not found'}), 404

    # Return event details
    return jsonify({'success': True, 'event': {
        'id': event.id,
        'name': event.name,
        'description': event.description
    }}), 200

# Define the route for updating event details
@app.route('/api/event/<int:event_id>/update', methods=['PUT'])
def update_event(event_id):
    # Retrieve JSON data from the request
    data = request.json
    name = data.get('name')
    description = data.get('description')

    # Retrieve the event from the database
    event = Event.query.get(event_id)
    if not event:
        return jsonify({'success': False, 'message': 'Event not found'}), 404

    # Update event details
    if name:
        event.name = name
    if description:
        event.description = description

    try:
        # Commit the transaction to save the updated event details
        db.session.commit()
        # Return a JSON response indicating successful update
        return jsonify({'success': True, 'message': 'Event details updated successfully'}), 200
    except Exception as e:
        # Rollback the transaction in case of any error
        db.session.rollback()
        # Return a JSON response indicating update failed
        return jsonify({'success': False, 'message': 'Failed to update event details. Please try again later'}), 500

# Define the route for canceling an event
@app.route('/api/event/<int:event_id>/cancel', methods=['DELETE'])
def cancel_event(event_id):
    # Retrieve the event from the database
    event = Event.query.get(event_id)
    if not event:
        return jsonify({'success': False, 'message': 'Event not found'}), 404

    try:
        # Delete the event from the database
        db.session.delete(event)
        db.session.commit()
        # Return a JSON response indicating successful cancellation
        return jsonify({'success': True, 'message': 'Event canceled successfully'}), 200
    except Exception as e:
        # Rollback the transaction in case of any error
        db.session.rollback()
        # Return a JSON response indicating cancellation failed
        return jsonify({'success': False, 'message': 'Failed to cancel event. Please try again later'}), 500

# Define the route for subscribing to an event
@app.route('/api/events/<int:event_id>/subscribe', methods=['POST'])
def subscribe_to_event():
    # Retrieve JSON data from the request
    data = request.json
    user_id = data.get('user_id')
    event_id = data.get('event_id')

    # Check if the subscription already exists
    existing_subscription = EventSubscription.query.filter_by(user_id=user_id, event_id=event_id).first()
    if existing_subscription:
        return jsonify({'success': False, 'message': 'You are already subscribed to this event'}), 400

    # Create a new EventSubscription object
    new_subscription = EventSubscription(user_id=user_id, event_id=event_id)

    # Add the new subscription to the database session
    db.session.add(new_subscription)

    try:
        # Commit the transaction to save the new subscription to the database
        db.session.commit()
        # Return a JSON response indicating successful subscription
        return jsonify({'success': True, 'message': 'Subscribed to event successfully'}), 201
    except Exception as e:
        # Rollback the transaction in case of any error
        db.session.rollback()
        # Return a JSON response indicating subscription failed
        return jsonify({'success': False, 'message': 'Failed to subscribe to event. Please try again later'}), 500

# Define the route for unsubscribing from an event
@app.route('/api/events/<int:event_id>/unsubscribe', methods=['POST'])
def unsubscribe_from_event():
    # Retrieve JSON data from the request
    data = request.json
    user_id = data.get('user_id')
    event_id = data.get('event_id')

    # Find the subscription to delete
    subscription_to_delete = EventSubscription.query.filter_by(user_id=user_id, event_id=event_id).first()
    if not subscription_to_delete:
        return jsonify({'success': False, 'message': 'You are not subscribed to this event'}), 400

    # Delete the subscription from the database session
    db.session.delete(subscription_to_delete)

    try:
        # Commit the transaction to delete the subscription from the database
        db.session.commit()
        # Return a JSON response indicating successful unsubscription
        return jsonify({'success': True, 'message': 'Unsubscribed from event successfully'}), 200
    except Exception as e:
        # Rollback the transaction in case of any error
        db.session.rollback()
        # Return a JSON response indicating unsubscription failed
        return jsonify({'success': False, 'message': 'Failed to unsubscribe from event. Please try again later'}), 500

# Define the route for scheduling a pickup
@app.route('/api/pickups/schedule', methods=['POST'])
def schedule_pickup():
    # Retrieve JSON data from the request
    data = request.json
    user_id = data.get('user_id')
    event_id = data.get('event_id')
    longitude = data.get('longitude')
    pickup_time = data.get('pickup_time')

    # Retrieve all users subscribed to the event
    users = User.query.join(EventSubscription).filter(EventSubscription.event_id == event_id).all()

    # Retrieve driver's location
    driver_latitude = data.get('driver_latitude')
    driver_longitude = data.get('driver_longitude')

    # Compute routes for the driver using Dijkstra's Algorithm with ETA
    routes_with_eta = compute_routes_with_eta(driver_latitude, driver_longitude, users)

    # Sort users by route distance
    sorted_users = sorted(routes_with_eta.items(), key=lambda x: x[1]['distance'])

    # Send notification to all users that pickup has commenced
    for user_id, _ in sorted_users:
        send_notification(user_id, "Pickup has commenced")

    # Send notification to the user who is next to be picked
    next_user_id, next_user_data = sorted_users[0]
    send_notification(next_user_id, "Driver is on the way to your location")

    # Save pickup requests to the database
    for user_id, _ in sorted_users:
        pickup_request = PickupRequest(user_id=user_id, event_id=event_id,
                                       latitude=users[user_id].latitude, longitude=users[user_id].longitude)
        db.session.add(pickup_request)

    db.session.commit()

    return jsonify({'success': True, 'message': 'Pickup requests received'}), 201

    # Retrieve JSON data from the request
    data = request.json   
    user_id = data.get('user_id')  
    event_id = data.get('event_id')   
    longitude = data.get('longitude')   
    pickup_time = data.get('pickup_time')
    
    # Retrieve all users subscribed to the event
    users = User.query.join(EventSubscription).filter(EventSubscription.event_id == event_id).all()
    
    # Retrieve driver's location
    driver_latitude = data.get('driver_latitude')   
    driver_longitude = data.get('driver_longitude')   
    
    # Compute routes for the driver using Dijkstra's Algorithm with ETA
    routes_with_eta = compute_routes_with_eta(driver_latitude, driver_longitude, users)
    
    # Sort users by route distance
    sorted_users = sorted(routes_with_eta.items(), key=lambda x: x[1]['distance'])
    
    # Send notification to all users that pickup has commenced
    for user_id, _ in sorted_users:
        send_notification(user_id, "Pickup has commenced")
    
    # Send notification to the user who is next to be picked
    next_user_id, next_user_data = sorted_users[0]
    send_notification(next_user_id, "Driver is on the way to your location")

    # Save pickup requests to the database
    for user_id, _ in sorted_users:
        pickup_request = PickupRequest(user_id=user_id, event_id=event_id, latitude=users[user_id].latitude, longitude=users[user_id].longitude)   
        db.session.add(pickup_request)   
    
    db.session.commit()   

    return jsonify({'success': True, 'message': 'Pickup requests received'}), 201
    # Retrieve JSON data from the request
    data = request.json   
    user_id = data.get('user_id')  
    event_id = data.get('event_id')   
    longitude = data.get('longitude')   
    pickup_time = data.get('pickup_time')
    
    # Retrieve all users subscribed to the event
    users = User.query.join(EventSubscription).filter(EventSubscription.event_id == event_id).all()
    
    # Retrieve driver's location
    driver_latitude = data.get('driver_latitude')   
    driver_longitude = data.get('driver_longitude')   
    
    # Compute routes for the driver using Dijkstra's Algorithm
    routes = compute_routes(driver_latitude, driver_longitude, users)
    
    # Sort users by route distance
    sorted_users = sorted(routes.items(), key=lambda x: x[1])
    
    # Retrieve pickup order
    pickup_order = [user[0] for user in sorted_users]
    
    # Save pickup requests to the database
    for user_id in pickup_order:
        pickup_request = PickupRequest(user_id=user_id, event_id=event_id, latitude=users[user_id].latitude, longitude=users[user_id].longitude)   
        db.session.add(pickup_request)   
    
    db.session.commit()   

    return jsonify({'success': True, 'message': 'Pickup requests received'}), 201

# Define the route for canceling a pickup request
@app.route('/api/pickups/cancel', methods=['POST'])
def cancel_pickup_request():
    # Retrieve JSON data from the request
    data = request.json
    user_id = data.get('user_id')
    event_id = data.get('event_id')

    # Check if the pickup request exists
    pickup_request = PickupRequest.query.filter_by(user_id=user_id, event_id=event_id).first()
    if not pickup_request:
        return jsonify({'success': False, 'message': 'Pickup request not found'}), 404

    # Delete the pickup request from the database session
    db.session.delete(pickup_request)

    try:
        # Commit the transaction to delete the pickup request from the database
        db.session.commit()
        # Return a JSON response indicating successful cancellation
        return jsonify({'success': True, 'message': 'Pickup request canceled successfully'}), 200
    except Exception as e:
        # Rollback the transaction in case of any error
        db.session.rollback()
        # Return a JSON response indicating cancellation failed
        return jsonify({'success': False, 'message': 'Failed to cancel pickup request. Please try again later'}), 500

# Define the route for assigning a driver to an event
@app.route('/api/events/<int:event_id>/assign-driver', methods=['POST'])
def assign_driver_to_event():
    # Retrieve JSON data from the request
    data = request.json
    driver_id = data.get('driver_id')
    event_id = data.get('event_id')

    # Check if the driver exists
    driver = BusDriver.query.get(driver_id)
    if not driver:
        return jsonify({'success': False, 'message': 'Driver not found'}), 404

    # Assign the driver to the event
    event = Event.query.get(event_id)
    if not event:
        return jsonify({'success': False, 'message': 'Event not found'}), 404

    event.driver_id = driver_id

    try:
        # Commit the transaction to save the driver assignment to the event
        db.session.commit()
        # Return a JSON response indicating successful assignment
        return jsonify({'success': True, 'message': 'Driver assigned to event successfully'}), 200
    except Exception as e:
        # Rollback the transaction in case of any error
        db.session.rollback()
        # Return a JSON response indicating assignment failed
        return jsonify({'success': False, 'message': 'Failed to assign driver to event. Please try again later'}), 500

# Define the route for starting the pickup
@app.route('/api/pickup/start', methods=['POST'])
def start_pickup():
    # Retrieve JSON data from the request
    data = request.json
    driver_id = data.get('driver_id')
    event_id = data.get('event_id')

    # Check if the driver is assigned to the event
    event = Event.query.get(event_id)
    if not event:
        return jsonify({'success': False, 'message': 'Event not found'}), 404

    if event.assigned_driver_id != driver_id:
        return jsonify({'success': False, 'message': 'Driver is not assigned to this event'}), 400

    # Retrieve users subscribed to the event who have requested pickup
    users = User.query.join(EventSubscription).filter(EventSubscription.event_id == event_id).all()
    if not users:
        return jsonify({'success': False, 'message': 'No users have requested pickup for this event'}), 400

    # Notify all users that pickup has commenced
    notify_pickup_commenced(users)

    # Calculate routes with ETA for users
    driver_latitude = data.get('driver_latitude')
    driver_longitude = data.get('driver_longitude')
    routes_with_eta = compute_routes_with_eta(driver_latitude, driver_longitude, users)

    # Notify the next user in line
    next_user_id, next_user_data = min(routes_with_eta.items(), key=lambda x: x[1]['eta'])
    send_notification(next_user_id, f"Driver is on the way to your location. ETA: {next_user_data['eta']} minutes")

    return jsonify({'success': True, 'message': 'Pickup has commenced'}), 200
    # Retrieve JSON data from the request
    data = request.json
    driver_id = data.get('driver_id')
    event_id = data.get('event_id')

    # Check if the driver is assigned to the event
    event = Event.query.get(event_id)
    if not event:
        return jsonify({'success': False, 'message': 'Event not found'}), 404

    if event.assigned_driver_id != driver_id:
        return jsonify({'success': False, 'message': 'Driver is not assigned to this event'}), 400

    # Retrieve users subscribed to the event who have requested pickup
    users = User.query.join(EventSubscription).filter(EventSubscription.event_id == event_id).all()
    if not users:
        return jsonify({'success': False, 'message': 'No users have requested pickup for this event'}), 400

    # Notify the users that pickup has commenced
    notify_pickup_commenced(users)

    return jsonify({'success': True, 'message': 'Pickup has commenced'}), 200

# Endpoint for attendees to search and filter events
@app.route('/api/events/search', methods=['GET'])
def search_events():
    # Retrieve query parameters from the request
    location = request.args.get('location')
    date = request.args.get('date')
    event_type = request.args.get('event_type')

    # Query events based on the provided criteria
    events_query = Event.query
    if location:
        events_query = events_query.filter(Event.location == location)
    if date:
        events_query = events_query.filter(Event.date == date)
    if event_type:
        events_query = events_query.filter(Event.type == event_type)

    # Execute the query and retrieve the events
    events = events_query.all()

    # Serialize the events data into JSON format
    serialized_events = [{'id': event.id, 'name': event.name, 'description': event.description} for event in events]

    return jsonify({'events': serialized_events}), 200

# Endpoint for organizers to filter and search for attendees or drivers
@app.route('/api/users/search', methods=['GET'])
def search_users():
    # Retrieve query parameters from the request
    user_type = request.args.get('user_type')  # Specify 'attendee' or 'driver'
    criteria1 = request.args.get('criteria1')   # Define your filter criteria
    criteria2 = request.args.get('criteria2')   # Define additional filter criteria if needed

    # Validate user type
    if user_type not in ['attendee', 'driver']:
        return jsonify({'message': 'Invalid user type. Use "attendee" or "driver".'}), 400

    # Query users based on the provided criteria
    users_query = User.query.filter(User.type == user_type)
    if criteria1:
        users_query = users_query.filter(User.criteria1 == criteria1)
    if criteria2:
        users_query = users_query.filter(User.criteria2 == criteria2)

    # Execute the query and retrieve the users
    users = users_query.all()

    # Serialize the users data into JSON format
    serialized_users = [{'id': user.id, 'username': user.username, 'email': user.email} for user in users]

    return jsonify({'users': serialized_users}), 200

# Define a function to compute the shortest path using Dijkstra's Algorithm
def dijkstra(graph, start, end):
    # Initialize distances with infinity for all nodes
    distances = {node: float('inf') for node in graph}
    distances[start] = 0

    # Priority queue to store nodes with the smallest distance
    priority_queue = [(0, start)]

    while priority_queue:
        current_distance, current_node = heapq.heappop(priority_queue)

        # Check if we reached the destination
        if current_node == end:
            return distances[end]

        # Check neighbors of the current node
        for neighbor, weight in graph[current_node].items():
            distance = current_distance + weight

            # Update distance if a shorter path is found
            if distance < distances[neighbor]:
                distances[neighbor] = distance
                heapq.heappush(priority_queue, (distance, neighbor))

    # If no path is found
    return float('inf')

def calculate_distance(lat1, lon1, lat2, lon2):
    # Radius of the Earth in kilometers
    R = 6371.0

    # Convert latitude and longitude from degrees to radians
    lat1_rad = radians(lat1)
    lon1_rad = radians(lon1)
    lat2_rad = radians(lat2)
    lon2_rad = radians(lon2)

    # Calculate the change in coordinates
    dlon = lon2_rad - lon1_rad
    dlat = lat2_rad - lat1_rad

    # Haversine formula
    a = sin(dlat / 2)**2 + cos(lat1_rad) * cos(lat2_rad) * sin(dlon / 2)**2
    c = 2 * atan2(sqrt(a), sqrt(1 - a))

    # Calculate distance
    distance = R * c

    return distance

# Function to send notifications
def send_notification(user_id, message):
    # Implement code to send notifications to users
    # For demonstration purposes, you can print the notification message
    print(f"Notification sent to User {user_id}: {message}")

# Function to calculate estimated time of arrival (ETA)
def calculate_eta(driver_latitude, driver_longitude, user_latitude, user_longitude):
    # Calculate distance between driver and user
    distance_km = calculate_distance(driver_latitude, driver_longitude, user_latitude, user_longitude)

    # Assuming an average speed of 30 km/h
    average_speed_kmh = 30

    # Calculate estimated time of arrival in hours
    eta_hours = distance_km / average_speed_kmh

    # Convert hours to minutes
    eta_minutes = eta_hours * 60

    return eta_minutes

# Update the route calculation function to include ETA notifications
def compute_routes_with_eta(driver_latitude, driver_longitude, users):
    routes_with_eta = {}
    for user in users:
        eta = calculate_eta(driver_latitude, driver_longitude, user.latitude, user.longitude)
        routes_with_eta[user.id] = {'distance': routes[user.id], 'eta': eta}
    return routes_with_eta

# Function to notify users that pickup has commenced
def notify_pickup_commenced(users):
    for user in users:
        send_notification(user.id, "Pickup has commenced")

# Run the Flask application
if __name__ == '__main__':
    with app.app_context():
        db.create_all()  
    app.run(debug=True)
