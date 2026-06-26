-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Host: 127.0.0.1
-- Generation Time: Apr 15, 2026 at 07:42 AM
-- Server version: 10.4.32-MariaDB
-- PHP Version: 8.2.12

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `my_app`
--

-- --------------------------------------------------------

--
-- Table structure for table `admin`
--

CREATE TABLE `admin` (
  `admin_id` int(1) NOT NULL,
  `admin_name` varchar(50) NOT NULL,
  `admin_email` varchar(50) NOT NULL,
  `admin_mobile` bigint(10) NOT NULL,
  `admin_pass` varchar(255) NOT NULL,
  `profile_image` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `admin`
--

INSERT INTO `admin` (`admin_id`, `admin_name`, `admin_email`, `admin_mobile`, `admin_pass`, `profile_image`) VALUES
(1, 'Kaushik Rathod .B', 'kaushikrathod6110@gmail.com', 7621925366, '$2b$12$wYjAWkAL8gLVSVvKeRI7fejMICit2QAymYCVtY6YdwawTqWSXqnYS', 'admin_1_0edc0161f1.png'),
(2, 'Kaushik Rathod.B', 'rathodkaushik1002@gmail.com', 1020102010, '$2b$12$s3IIPMjjkROE6xJ5ZGSwIugWDUM9EgtthSOwJGa0cvPp.VGUqjqwe', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `admin_notifications`
--

CREATE TABLE `admin_notifications` (
  `notification_id` int(11) NOT NULL,
  `title` varchar(255) NOT NULL,
  `message` text NOT NULL,
  `target_type` enum('all','user') NOT NULL DEFAULT 'all',
  `target_user_id` int(11) DEFAULT NULL,
  `created_by_admin_id` int(11) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `is_active` tinyint(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `admin_notifications`
--

INSERT INTO `admin_notifications` (`notification_id`, `title`, `message`, `target_type`, `target_user_id`, `created_by_admin_id`, `created_at`, `is_active`) VALUES
(1, 'Welcome', 'Welcome to my App😊', 'all', NULL, 2, '2026-04-10 12:51:08', 0);

-- --------------------------------------------------------

--
-- Table structure for table `app_feedback`
--

CREATE TABLE `app_feedback` (
  `feedback_id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `rating` int(11) NOT NULL,
  `comment` text DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `app_feedback`
--

INSERT INTO `app_feedback` (`feedback_id`, `user_id`, `rating`, `comment`, `created_at`) VALUES
(1, 8, 3, '', '2026-04-11 20:42:30');

-- --------------------------------------------------------

--
-- Table structure for table `block_requests`
--

CREATE TABLE `block_requests` (
  `request_id` int(11) NOT NULL,
  `account_type` enum('user','seller','delivery_staff') NOT NULL,
  `account_id` int(11) NOT NULL,
  `email` varchar(200) NOT NULL,
  `message` text NOT NULL,
  `request_status` enum('pending','accepted','deleted') NOT NULL DEFAULT 'pending',
  `requested_at` datetime NOT NULL DEFAULT current_timestamp(),
  `cooldown_until` datetime NOT NULL,
  `accepted_at` datetime DEFAULT NULL,
  `deleted_at` datetime DEFAULT NULL,
  `admin_note` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `block_requests`
--

INSERT INTO `block_requests` (`request_id`, `account_type`, `account_id`, `email`, `message`, `request_status`, `requested_at`, `cooldown_until`, `accepted_at`, `deleted_at`, `admin_note`) VALUES
(2, 'user', 8, 'divya014@gmail.com', 'Sorry!😢', 'accepted', '2026-04-04 23:16:04', '2026-04-11 23:16:04', '2026-04-04 23:16:33', NULL, NULL),
(3, 'user', 1, 'kashish01@gmail.com', 'please, unblock my account.', 'accepted', '2026-04-07 12:21:02', '2026-04-14 12:21:02', '2026-04-07 12:22:09', NULL, NULL);

-- --------------------------------------------------------

--
-- Table structure for table `cart`
--

CREATE TABLE `cart` (
  `cart_id` int(5) NOT NULL,
  `user_id` int(5) NOT NULL,
  `seller_id` int(11) NOT NULL,
  `prod_id` int(5) DEFAULT NULL,
  `quantity` int(11) NOT NULL,
  `price_at_time` decimal(10,2) NOT NULL,
  `total_price` decimal(10,2) NOT NULL,
  `added_at` datetime DEFAULT current_timestamp(),
  `cart_status` enum('Active','Removed','Ordered') NOT NULL,
  `updated_at` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `cart`
--

INSERT INTO `cart` (`cart_id`, `user_id`, `seller_id`, `prod_id`, `quantity`, `price_at_time`, `total_price`, `added_at`, `cart_status`, `updated_at`) VALUES
(1, 6, 1, 1, 2, 45.00, 100.00, '2026-03-03 23:12:26', 'Active', '2026-03-24 18:22:38'),
(2, 8, 3, 2, 3, 90.00, 270.00, '2026-03-21 20:53:00', 'Removed', '2026-04-14 12:30:44'),
(3, 2, 1, 3, 3, 180.00, 540.00, '2026-03-24 18:24:42', 'Ordered', '2026-03-31 18:50:29'),
(4, 1, 1, 5, 1, 40.00, 40.00, '2026-03-30 14:04:34', 'Ordered', '2026-04-01 12:15:10'),
(5, 1, 1, 1, 1, 50.00, 50.00, '2026-03-30 14:05:01', 'Removed', '2026-03-30 19:29:57'),
(6, 1, 1, 4, 1, 95.00, 95.00, '2026-03-30 23:51:48', 'Ordered', '2026-03-30 23:51:48'),
(7, 1, 1, 4, 1, 95.00, 95.00, '2026-03-30 23:52:05', 'Ordered', '2026-03-30 23:52:05'),
(8, 1, 1, 4, 1, 95.00, 95.00, '2026-03-30 23:53:04', 'Ordered', '2026-03-30 23:53:04'),
(9, 1, 1, 5, 1, 40.00, 40.00, '2026-03-31 01:46:27', 'Ordered', '2026-03-31 01:46:27'),
(10, 2, 1, 5, 1, 40.00, 40.00, '2026-03-31 18:47:14', 'Removed', '2026-03-31 18:47:23'),
(11, 2, 1, 4, 2, 95.00, 190.00, '2026-03-31 22:21:54', 'Ordered', '2026-03-31 22:21:54'),
(12, 2, 1, 4, 1, 95.00, 95.00, '2026-03-31 22:53:18', 'Active', '2026-03-31 22:53:18'),
(13, 2, 3, 2, 3, 90.00, 270.00, '2026-03-31 22:54:32', 'Ordered', '2026-03-31 22:54:32'),
(14, 2, 1, 1, 2, 50.00, 100.00, '2026-03-31 23:16:10', 'Removed', '2026-04-05 16:14:20'),
(15, 2, 1, 1, 2, 50.00, 100.00, '2026-03-31 23:16:23', 'Ordered', '2026-03-31 23:16:23'),
(16, 1, 1, 1, 2, 50.00, 100.00, '2026-03-31 23:23:27', 'Removed', '2026-03-31 23:23:46'),
(17, 1, 1, 1, 3, 50.00, 150.00, '2026-03-31 23:24:17', 'Ordered', '2026-03-31 23:24:17'),
(18, 1, 3, 2, 1, 90.00, 90.00, '2026-04-01 11:29:18', 'Ordered', '2026-04-01 12:15:10'),
(19, 1, 1, 5, 1, 40.00, 40.00, '2026-04-01 12:07:11', 'Ordered', '2026-04-01 12:07:11'),
(20, 1, 1, 3, 3, 180.00, 540.00, '2026-04-01 12:08:09', 'Ordered', '2026-04-01 12:08:09'),
(21, 1, 1, 4, 1, 95.00, 95.00, '2026-04-01 12:13:51', 'Ordered', '2026-04-01 12:15:10'),
(22, 1, 1, 5, 1, 40.00, 40.00, '2026-04-05 12:30:05', 'Removed', '2026-04-06 13:44:39'),
(23, 1, 1, 3, 1, 180.00, 180.00, '2026-04-05 12:30:06', 'Removed', '2026-04-06 13:44:39'),
(24, 1, 3, 2, 2, 90.00, 180.00, '2026-04-05 12:30:17', 'Removed', '2026-04-06 13:44:38'),
(25, 1, 1, 5, 2, 40.00, 80.00, '2026-04-06 13:44:44', 'Removed', '2026-04-09 11:46:33'),
(26, 1, 1, 3, 3, 180.00, 540.00, '2026-04-07 12:38:57', 'Ordered', '2026-04-09 11:47:01'),
(27, 1, 3, 2, 2, 90.00, 180.00, '2026-04-07 12:39:21', 'Removed', '2026-04-09 11:46:36'),
(28, 1, 3, 2, 1, 90.00, 90.00, '2026-04-09 11:46:47', 'Ordered', '2026-04-09 11:47:01'),
(29, 1, 3, 2, 1, 90.00, 90.00, '2026-04-09 12:13:22', 'Ordered', '2026-04-09 12:32:57'),
(30, 1, 1, 5, 1, 40.00, 40.00, '2026-04-09 12:13:30', 'Ordered', '2026-04-09 12:32:57'),
(31, 1, 1, 5, 1, 40.00, 40.00, '2026-04-09 12:48:09', 'Ordered', '2026-04-09 12:48:29'),
(32, 1, 3, 2, 1, 90.00, 90.00, '2026-04-09 12:48:14', 'Ordered', '2026-04-09 12:48:29'),
(33, 1, 1, 3, 1, 180.00, 180.00, '2026-04-09 12:50:10', 'Ordered', '2026-04-09 12:50:54'),
(34, 1, 3, 2, 1, 90.00, 90.00, '2026-04-09 12:50:20', 'Ordered', '2026-04-09 12:50:54'),
(35, 8, 1, 1, 1, 50.00, 50.00, '2026-04-09 20:12:15', 'Removed', '2026-04-14 12:30:45'),
(36, 2, 1, 1, 1, 50.00, 50.00, '2026-04-09 20:12:48', 'Ordered', '2026-04-09 20:12:48'),
(37, 2, 1, 4, 2, 95.00, 190.00, '2026-04-09 22:32:57', 'Ordered', '2026-04-09 22:32:57'),
(38, 2, 1, 3, 1, 180.00, 180.00, '2026-04-09 22:34:47', 'Ordered', '2026-04-09 22:34:47'),
(39, 2, 1, 5, 1, 40.00, 40.00, '2026-04-09 22:52:24', 'Ordered', '2026-04-09 22:52:24'),
(40, 2, 1, 3, 1, 180.00, 180.00, '2026-04-09 22:54:51', 'Ordered', '2026-04-09 22:54:51'),
(41, 2, 1, 3, 1, 180.00, 180.00, '2026-04-09 23:06:34', 'Ordered', '2026-04-09 23:06:34'),
(42, 2, 1, 4, 1, 95.00, 95.00, '2026-04-10 00:04:27', 'Ordered', '2026-04-10 00:04:27'),
(43, 1, 3, 2, 1, 90.00, 90.00, '2026-04-10 00:16:47', 'Active', '2026-04-10 00:16:47'),
(44, 1, 1, 3, 1, 180.00, 180.00, '2026-04-10 00:16:49', 'Active', '2026-04-10 00:16:49'),
(45, 2, 3, 2, 1, 90.00, 90.00, '2026-04-11 14:06:40', 'Ordered', '2026-04-11 14:06:40'),
(46, 2, 3, 2, 1, 90.00, 90.00, '2026-04-11 14:08:08', 'Ordered', '2026-04-11 14:08:08'),
(47, 2, 1, 5, 1, 40.00, 40.00, '2026-04-11 14:09:25', 'Ordered', '2026-04-11 14:09:25'),
(48, 8, 1, 4, 1, 95.00, 95.00, '2026-04-11 19:27:55', 'Ordered', '2026-04-11 19:27:55'),
(49, 8, 1, 3, 1, 180.00, 180.00, '2026-04-11 19:30:59', 'Ordered', '2026-04-11 19:30:59'),
(50, 8, 1, 5, 1, 40.00, 40.00, '2026-04-11 19:37:34', 'Ordered', '2026-04-11 19:37:34'),
(51, 9, 3, 2, 1, 90.00, 90.00, '2026-04-11 21:35:26', 'Ordered', '2026-04-11 21:37:19'),
(52, 9, 1, 5, 1, 40.00, 40.00, '2026-04-11 21:35:27', 'Ordered', '2026-04-11 21:37:19'),
(53, 9, 1, 3, 1, 180.00, 180.00, '2026-04-11 21:35:29', 'Ordered', '2026-04-11 21:37:19'),
(54, 1, 1, 3, 1, 180.00, 180.00, '2026-04-14 12:13:31', 'Ordered', '2026-04-14 12:13:31'),
(55, 8, 1, 6, 1, 30.00, 30.00, '2026-04-14 12:23:17', 'Ordered', '2026-04-14 12:23:17'),
(56, 8, 1, 5, 1, 40.00, 40.00, '2026-04-14 12:30:37', 'Active', '2026-04-14 12:30:37'),
(57, 8, 1, 3, 1, 180.00, 180.00, '2026-04-14 12:31:05', 'Ordered', '2026-04-14 12:31:05'),
(58, 2, 1, 1, 3, 50.00, 150.00, '2026-04-14 13:00:04', 'Ordered', '2026-04-14 13:00:04'),
(59, 2, 1, 1, 1, 50.00, 50.00, '2026-04-14 13:57:23', 'Ordered', '2026-04-14 13:57:23'),
(60, 9, 1, 1, 1, 50.00, 50.00, '2026-04-14 14:12:07', 'Ordered', '2026-04-14 14:12:07'),
(61, 9, 1, 1, 1, 50.00, 50.00, '2026-04-14 14:23:36', 'Ordered', '2026-04-14 14:23:36'),
(62, 9, 1, 1, 1, 50.00, 50.00, '2026-04-14 14:33:26', 'Ordered', '2026-04-14 14:33:26'),
(63, 10, 8, 17, 1, 150.00, 150.00, '2026-04-14 20:01:03', 'Active', '2026-04-14 20:01:03'),
(64, 10, 7, 14, 1, 50.00, 50.00, '2026-04-14 20:01:46', 'Ordered', '2026-04-14 20:01:46');

-- --------------------------------------------------------

--
-- Table structure for table `category`
--

CREATE TABLE `category` (
  `category_id` int(5) NOT NULL,
  `category_name` varchar(50) NOT NULL,
  `description` text NOT NULL,
  `category_image` varchar(255) NOT NULL,
  `status` enum('active','inactive') NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `category`
--

INSERT INTO `category` (`category_id`, `category_name`, `description`, `category_image`, `status`) VALUES
(1, 'fruits', 'All Fruits', 'fruits.jpg', 'active'),
(2, 'Vegetables', 'All veg', 'Vegetables.jpg', 'active'),
(3, 'oils', 'All types of oils', 'oil.jpg', 'active'),
(4, 'Biscuits', 'All types of Biscuits', 'category_f12afcc83d7e.png', 'active'),
(5, 'Masalas', 'All types of Masalas', 'category_d45239891474.jpeg', 'active'),
(6, 'Dairy & Bakery', 'All types of Dairy & Bakery', 'category_4566dceaed55.webp', 'active'),
(7, 'Snacks', 'All types of Snacks', 'category_14c17f238118.jpeg', 'active'),
(8, 'cold drinks', 'All types of cold drinks', 'category_0e7750234f89.jpeg', 'active'),
(9, 'Chocolates', 'All types of chocolates', 'category_e893bf79aacd.jpg', 'active'),
(10, 'Dry Fruits & Nuts', 'All types of Dry Fruits & Nuts', 'category_4ea714392a6c.jpg', 'active');

-- --------------------------------------------------------

--
-- Table structure for table `delivery`
--

CREATE TABLE `delivery` (
  `delivery_id` int(8) NOT NULL,
  `order_id` int(8) NOT NULL,
  `delivery_staff_id` int(5) NOT NULL,
  `delivery_date` datetime NOT NULL,
  `delivery_address` text NOT NULL,
  `delivery_pincode` int(11) NOT NULL,
  `delivery_status` enum('Pending','OutForDelivery','Delivered','Failed','Cancelled') NOT NULL,
  `notes` text NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `delivery`
--

INSERT INTO `delivery` (`delivery_id`, `order_id`, `delivery_staff_id`, `delivery_date`, `delivery_address`, `delivery_pincode`, `delivery_status`, `notes`) VALUES
(1, 1, 1, '2026-03-08 15:56:53', '22/224 krishnanagar, ahmedabad', 382001, 'Delivered', 'good food'),
(2, 2, 1, '2026-02-10 15:52:12', '28/224 maninagar, ahmedabad', 381001, 'Delivered', 'good food'),
(3, 3, 1, '2026-03-08 16:09:21', 'gomtipur, ahmedabad', 380021, 'Delivered', 'good veg'),
(4, 4, 1, '2026-03-10 17:02:25', 'Ashram Road, Ahmedabad', 388001, 'Delivered', 'good food'),
(5, 5, 1, '2026-03-21 20:53:07', '10/102 dakshini,maninagar', 380092, 'Delivered', 'Good oil'),
(6, 6, 2, '2026-03-28 12:49:45', '22/124 amraiwadi, ahmedabad', 386500, 'Delivered', 'Good Fruits'),
(7, 10, 4, '2026-03-31 01:46:27', 'amraiwadi', 380001, 'Delivered', ''),
(8, 18, 1, '2026-04-14 11:31:42', 'amraiwadi', 380001, 'Delivered', ''),
(9, 19, 1, '2026-04-01 12:33:01', 'amraiwadi', 380001, 'Delivered', ''),
(10, 16, 1, '2026-04-01 12:07:11', 'amraiwadi', 380001, 'Delivered', ''),
(11, 36, 4, '2026-04-11 14:09:25', 'nikol', 380020, 'Delivered', ''),
(12, 35, 4, '2026-04-11 14:17:19', 'nikol', 380020, '', ''),
(13, 34, 4, '2026-04-11 14:21:14', 'nikol', 380020, '', ''),
(14, 17, 2, '2026-04-13 12:45:21', 'amraiwadi', 380001, '', ''),
(15, 20, 2, '2026-04-13 12:45:25', 'amraiwadi', 380001, '', ''),
(16, 21, 2, '2026-04-09 11:47:01', 'amraiwadi', 380001, 'Delivered', ''),
(17, 22, 2, '2026-04-09 11:47:01', 'amraiwadi', 380001, 'Delivered', ''),
(18, 49, 2, '2026-04-14 20:02:56', '24/226, manhar nagar society, gomtipur', 380021, '', ''),
(19, 23, 2, '2026-04-14 20:04:32', 'amraiwadi', 380001, '', '');

-- --------------------------------------------------------

--
-- Table structure for table `delivery_staff`
--

CREATE TABLE `delivery_staff` (
  `delivery_staff_id` int(5) NOT NULL,
  `delivery_staff_name` varchar(100) NOT NULL,
  `d_s_mobile` bigint(10) NOT NULL,
  `d_s_email` varchar(200) NOT NULL,
  `d_s_pass` varchar(255) NOT NULL,
  `d_s_address` text NOT NULL,
  `d_s_pincode` int(11) NOT NULL,
  `vehicle_type` enum('Bike','Scooter','Cycle','None') NOT NULL,
  `staff_licence_no` varchar(30) NOT NULL,
  `aadhar_card_no` varchar(12) NOT NULL,
  `profile_image` varchar(255) DEFAULT NULL,
  `d_s_status` enum('Active','Inactive') NOT NULL,
  `joining_date` date NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `delivery_staff`
--

INSERT INTO `delivery_staff` (`delivery_staff_id`, `delivery_staff_name`, `d_s_mobile`, `d_s_email`, `d_s_pass`, `d_s_address`, `d_s_pincode`, `vehicle_type`, `staff_licence_no`, `aadhar_card_no`, `profile_image`, `d_s_status`, `joining_date`) VALUES
(1, 'virat sharma', 1111111111, 'virat18@gmail.com', '$2b$12$0cwRVRpeyaWMriPxTQi3u.5BEBgmUaTZuXNEkl3uUzQtj5zcLPnru', '22/224 bhulabhai park, kankariya, ahmedabad', 380010, 'Scooter', 'DL-142011001234', '000000000001', 'delivery_staff_f95b7c1f271b4670a483bd4c4fe702e1.png', 'Active', '2026-03-08'),
(2, 'Raju patel', 6600990011, 'raju11@gmail.com', '$2b$12$5hHb0o5OLkIamzCaoP11Xev/AM2WQ76ro.5DmhwsJIPLZDshVovSe', 'krishananagar', 382345, 'Bike', 'GJ01 20240012345', '111111111111', NULL, 'Active', '2026-03-24'),
(3, 'mahesh', 1234569870, 'mahesh22@gmail.com', '$2b$12$/2MlCv8p69V0ea7tgDq22OI/dvkqAg2M3FJMtiHcZz6TATzemuZEq', 'gomtipur', 380021, 'Scooter', 'rijgerkpgmeg[p', '000000000002', 'delivery_staff_c2b61a05d73a4987997e738339d2fe71.png', 'Active', '2026-03-25'),
(4, 'Mahavir yogi', 4554455445, 'yogi20@gmail.com', '$2b$12$sWP3SmDFdoIH866m.JcLLO6K8IUnq64xXX43AP.eICej89FgsBIke', 'krishnanagar', 380080, 'Bike', 'GJ 095513', '123455675384', NULL, 'Active', '2026-03-26');

-- --------------------------------------------------------

--
-- Table structure for table `delivery_staff_reviews`
--

CREATE TABLE `delivery_staff_reviews` (
  `delivery_review_id` int(11) NOT NULL,
  `order_id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `delivery_staff_id` int(11) NOT NULL,
  `rating` int(11) DEFAULT NULL,
  `review` text DEFAULT NULL,
  `review_tags` text DEFAULT NULL,
  `is_skipped` tinyint(1) NOT NULL DEFAULT 0,
  `skipped_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ;

--
-- Dumping data for table `delivery_staff_reviews`
--

INSERT INTO `delivery_staff_reviews` (`delivery_review_id`, `order_id`, `user_id`, `delivery_staff_id`, `rating`, `review`, `review_tags`, `is_skipped`, `skipped_at`, `created_at`, `updated_at`) VALUES
(1, 5, 8, 1, 4, 'nice', '[\"Fast delivery\"]', 0, NULL, '2026-04-09 21:24:09', '2026-04-09 21:24:09'),
(2, 19, 1, 1, NULL, NULL, NULL, 1, '2026-04-10 11:42:12', '2026-04-10 11:42:12', '2026-04-10 11:42:12'),
(3, 16, 1, 1, 4, 'nice', '[\"Good behavior\"]', 0, NULL, '2026-04-10 14:44:46', '2026-04-10 14:44:46');

-- --------------------------------------------------------

--
-- Table structure for table `orders`
--

CREATE TABLE `orders` (
  `order_id` int(8) NOT NULL,
  `seller_id` int(5) DEFAULT NULL,
  `cart_id` int(5) DEFAULT NULL,
  `user_id` int(11) NOT NULL,
  `delivery_staff_id` int(11) DEFAULT NULL,
  `order_date` datetime NOT NULL,
  `total_amount` decimal(10,2) NOT NULL,
  `payment_method` enum('Online','COD') NOT NULL,
  `payment_status` enum('Paid','Pending','Failed') NOT NULL,
  `order_status` enum('Pending','Confirmed','Packed','OutForDelivery','Delivered','Cancelled') NOT NULL,
  `delivery_address` text NOT NULL,
  `pincode` varchar(10) DEFAULT NULL,
  `notes` text DEFAULT NULL,
  `delivery_status` enum('Unassigned','Assigned','Picked Up','Out For Delivery','Delivered','Cancelled') NOT NULL DEFAULT 'Unassigned',
  `assigned_at` datetime DEFAULT NULL,
  `picked_at` datetime DEFAULT NULL,
  `out_for_delivery_at` datetime DEFAULT NULL,
  `delivered_at` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `orders`
--

INSERT INTO `orders` (`order_id`, `seller_id`, `cart_id`, `user_id`, `delivery_staff_id`, `order_date`, `total_amount`, `payment_method`, `payment_status`, `order_status`, `delivery_address`, `pincode`, `notes`, `delivery_status`, `assigned_at`, `picked_at`, `out_for_delivery_at`, `delivered_at`) VALUES
(1, 3, 1, 7, 1, '2026-03-08 11:18:41', 500.00, 'Online', 'Paid', 'Delivered', '22/224 krishnanagar, ahmedabad', '382001', 'good food', 'Delivered', '2026-03-08 10:48:41', '2026-03-08 12:48:41', '2026-03-08 14:48:41', '2026-03-08 15:56:53'),
(2, 1, 1, 6, 1, '2026-02-10 15:52:12', 160.00, 'COD', 'Paid', 'Delivered', '28/224 maninagar, ahmedabad', '381001', 'good food', 'Delivered', '2026-02-10 11:52:12', '2026-02-10 12:52:12', '2026-02-10 15:52:12', '2026-03-08 16:06:26'),
(3, 4, 1, 1, 1, '2026-03-11 16:57:13', 400.00, 'Online', 'Paid', 'Delivered', 'gomtipur, ahmedabad', '380021', 'good veg', 'Delivered', '2026-03-11 15:23:13', '2026-03-11 15:30:13', '2026-03-08 15:54:13', '2026-03-08 16:09:21'),
(4, 1, 1, 2, 1, '2026-03-10 12:32:21', 660.00, 'Online', 'Paid', 'Delivered', 'Ashram Road, Ahmedabad', '388001', 'good food', 'Delivered', '2026-03-10 16:02:22', '2026-03-10 16:27:22', '2026-03-10 16:46:22', '2026-03-10 17:02:25'),
(5, 3, 2, 8, 1, '2026-03-21 16:23:07', 180.00, 'Online', 'Paid', 'Delivered', '10/102 dakshini,maninagar', '380092', 'Good oil', 'Delivered', '2026-03-20 20:06:07', '2026-03-21 07:53:07', '2026-03-21 12:53:07', '2026-03-21 20:53:07'),
(6, 1, 3, 2, 2, '2026-03-24 15:55:17', 180.00, 'COD', 'Paid', 'Delivered', '22/124 amraiwadi, ahmedabad', '386500', 'Good Fruits ', 'Delivered', '2026-03-24 20:37:01', '2026-03-28 12:47:39', '2026-03-28 12:49:45', '2026-03-24 20:39:18'),
(10, 1, 9, 1, 4, '2026-03-31 01:46:27', 40.00, 'COD', 'Paid', 'Delivered', 'amraiwadi', '380001', '', 'Delivered', '2026-03-31 18:28:40', '2026-03-31 18:29:53', '2026-03-31 18:32:22', '2026-03-31 18:32:26'),
(11, 1, 3, 2, NULL, '2026-03-31 18:50:29', 540.00, 'Online', 'Paid', 'Cancelled', 'nikol', '380020', 'Cancelled by user', 'Cancelled', NULL, NULL, NULL, NULL),
(12, 1, 11, 2, 1, '2026-03-31 22:21:54', 190.00, 'COD', 'Pending', 'Pending', 'nikol', '380020', NULL, 'Assigned', '2026-04-09 11:54:02', NULL, NULL, NULL),
(13, 3, 13, 2, NULL, '2026-03-31 22:54:32', 270.00, 'Online', 'Paid', 'Cancelled', 'nikol', '380020', 'Cancelled by user', 'Cancelled', NULL, NULL, NULL, NULL),
(14, 1, 15, 2, NULL, '2026-03-31 23:16:23', 100.00, 'COD', 'Pending', 'Cancelled', 'nikol', '380020', 'Cancelled by user', 'Cancelled', NULL, NULL, NULL, NULL),
(15, 1, 17, 1, 1, '2026-03-31 23:24:17', 150.00, 'Online', 'Paid', 'Pending', 'amraiwadi', '380001', NULL, 'Assigned', '2026-04-09 11:54:09', NULL, NULL, NULL),
(16, 1, 19, 1, 1, '2026-04-01 12:07:11', 40.00, 'COD', 'Paid', 'Delivered', 'amraiwadi', '380001', '', 'Delivered', '2026-04-01 12:33:23', '2026-04-01 12:33:31', '2026-04-01 12:34:55', '2026-04-01 12:34:58'),
(17, 1, 20, 1, 2, '2026-04-01 12:08:09', 540.00, 'Online', 'Paid', 'Pending', 'amraiwadi', '380001', NULL, 'Assigned', '2026-04-13 12:45:21', NULL, NULL, NULL),
(18, 1, 4, 1, 1, '2026-04-01 12:15:10', 40.00, 'Online', 'Paid', 'Delivered', 'amraiwadi', '380001', '', 'Delivered', '2026-04-01 12:31:20', '2026-04-01 12:31:31', '2026-04-01 12:31:38', '2026-04-14 11:31:42'),
(19, 3, 18, 1, 1, '2026-04-01 12:15:10', 90.00, 'Online', 'Paid', 'Delivered', 'amraiwadi', '380001', '', 'Delivered', '2026-04-01 12:31:56', '2026-04-01 12:32:51', '2026-04-01 12:32:53', '2026-04-01 12:33:01'),
(20, 1, 21, 1, 2, '2026-04-01 12:15:10', 95.00, 'Online', 'Paid', 'Pending', 'amraiwadi', '380001', NULL, 'Assigned', '2026-04-13 12:45:25', NULL, NULL, NULL),
(21, 1, 26, 1, 2, '2026-04-09 11:47:01', 540.00, 'COD', 'Paid', 'Delivered', 'amraiwadi', '380001', '', 'Delivered', '2026-04-13 12:45:28', '2026-04-13 12:45:47', '2026-04-13 12:45:50', '2026-04-13 12:46:04'),
(22, 3, 28, 1, 2, '2026-04-09 11:47:01', 90.00, 'COD', 'Paid', 'Delivered', 'amraiwadi', '380001', '', 'Delivered', '2026-04-13 12:46:10', '2026-04-14 20:02:39', '2026-04-14 20:02:41', '2026-04-14 20:02:42'),
(23, 3, 29, 1, 2, '2026-04-09 12:32:57', 90.00, 'COD', 'Pending', 'Pending', 'amraiwadi', '380001', NULL, 'Assigned', '2026-04-14 20:04:32', NULL, NULL, NULL),
(24, 1, 30, 1, NULL, '2026-04-09 12:32:57', 40.00, 'COD', 'Pending', 'Pending', 'amraiwadi', '380001', NULL, 'Unassigned', NULL, NULL, NULL, NULL),
(25, 1, 31, 1, NULL, '2026-04-09 12:48:29', 130.00, 'COD', 'Pending', 'Pending', 'amraiwadi', '380001', NULL, 'Unassigned', NULL, NULL, NULL, NULL),
(26, 1, 33, 1, NULL, '2026-04-09 12:50:54', 270.00, 'COD', 'Pending', 'Pending', 'amraiwadi', '380001', NULL, 'Unassigned', NULL, NULL, NULL, NULL),
(27, 1, 36, 2, NULL, '2026-04-09 20:12:48', 50.00, 'COD', 'Pending', 'Pending', 'nikol', '380020', NULL, 'Unassigned', NULL, NULL, NULL, NULL),
(28, 1, 37, 2, NULL, '2026-04-09 22:32:57', 190.00, 'COD', 'Pending', 'Pending', 'nikol', '380020', NULL, 'Unassigned', NULL, NULL, NULL, NULL),
(29, 1, 38, 2, NULL, '2026-04-09 22:34:47', 180.00, 'COD', 'Pending', 'Pending', 'nikol', '380020', NULL, 'Unassigned', NULL, NULL, NULL, NULL),
(30, 1, 39, 2, NULL, '2026-04-09 22:52:24', 40.00, 'COD', 'Pending', 'Cancelled', 'nikol', '380020', 'Cancelled by user', 'Cancelled', NULL, NULL, NULL, NULL),
(31, 1, 40, 2, NULL, '2026-04-09 22:54:51', 180.00, 'COD', 'Pending', 'Pending', 'nikol', '380020', NULL, 'Unassigned', NULL, NULL, NULL, NULL),
(32, 1, 41, 2, NULL, '2026-04-09 23:06:34', 180.00, 'COD', 'Pending', 'Pending', 'nikol', '380020', NULL, 'Unassigned', NULL, NULL, NULL, NULL),
(33, 1, 42, 2, NULL, '2026-04-10 00:04:27', 95.00, 'COD', 'Pending', 'Pending', 'nikol', '380020', NULL, 'Unassigned', NULL, NULL, NULL, NULL),
(34, 3, 45, 2, 4, '2026-04-11 14:06:40', 90.00, 'Online', 'Pending', 'Pending', 'nikol', '380020', NULL, 'Assigned', '2026-04-11 14:21:14', NULL, NULL, NULL),
(35, 3, 46, 2, 4, '2026-04-11 14:08:08', 90.00, 'Online', 'Paid', 'Pending', 'nikol', '380020', NULL, 'Assigned', '2026-04-11 14:17:19', NULL, NULL, NULL),
(36, 1, 47, 2, 4, '2026-04-11 14:09:25', 40.00, 'COD', 'Paid', 'Delivered', 'nikol', '380020', '', 'Delivered', '2026-04-11 14:10:27', '2026-04-11 14:10:39', '2026-04-11 14:10:47', '2026-04-11 14:10:50'),
(37, 1, 48, 8, NULL, '2026-04-11 19:27:55', 95.00, 'Online', 'Paid', 'Pending', 'gomtipur', '380040', NULL, 'Unassigned', NULL, NULL, NULL, NULL),
(38, 1, 49, 8, NULL, '2026-04-11 19:30:59', 180.00, 'Online', 'Pending', 'Cancelled', 'gomtipur', '380040', 'Cancelled by user', 'Cancelled', NULL, NULL, NULL, NULL),
(39, 1, 50, 8, NULL, '2026-04-11 19:37:34', 40.00, 'Online', 'Paid', 'Pending', 'gomtipur', '380040', NULL, 'Unassigned', NULL, NULL, NULL, NULL),
(40, 3, 51, 9, NULL, '2026-04-11 21:37:19', 310.00, 'COD', 'Pending', 'Pending', 'maninagar', '380070', NULL, 'Unassigned', NULL, NULL, NULL, NULL),
(41, 1, 54, 1, NULL, '2026-04-14 12:13:31', 207.00, 'COD', 'Pending', 'Pending', 'amraiwadi', '380001', NULL, 'Unassigned', NULL, NULL, NULL, NULL),
(42, 1, 55, 8, NULL, '2026-04-14 12:23:17', 57.00, 'Online', 'Pending', 'Cancelled', 'gomtipur', '380040', 'Cancelled by user', 'Cancelled', NULL, NULL, NULL, NULL),
(43, 1, 57, 8, NULL, '2026-04-14 12:31:05', 207.00, 'Online', 'Pending', 'Cancelled', 'gomtipur', '380040', 'Cancelled by user', 'Cancelled', NULL, NULL, NULL, NULL),
(44, 1, 58, 2, NULL, '2026-04-14 13:00:04', 177.00, 'COD', 'Pending', 'Cancelled', 'nikol', '380020', 'Cancelled by user', 'Cancelled', NULL, NULL, NULL, NULL),
(45, 1, 59, 2, NULL, '2026-04-14 13:57:23', 77.00, 'COD', 'Pending', 'Cancelled', 'nikol', '380020', 'Cancelled by user', 'Cancelled', NULL, NULL, NULL, NULL),
(46, 1, 60, 9, NULL, '2026-04-14 14:12:07', 77.00, 'COD', 'Pending', 'Cancelled', 'amraiwadi', '380055', 'Cancelled by user', 'Cancelled', NULL, NULL, NULL, NULL),
(47, 1, 61, 9, NULL, '2026-04-14 14:23:36', 77.00, 'COD', 'Pending', 'Pending', 'amraiwadi', '385050', NULL, 'Unassigned', NULL, NULL, NULL, NULL),
(48, 1, 62, 9, NULL, '2026-04-14 14:33:26', 77.00, 'COD', 'Pending', 'Cancelled', 'amraiwadi', '385050', 'Cancelled by user', 'Cancelled', NULL, NULL, NULL, NULL),
(49, 7, 64, 10, 2, '2026-04-14 20:01:46', 77.00, 'Online', 'Paid', 'Cancelled', '24/226, manhar nagar society, gomtipur', '380021', 'Cancelled by user', 'Cancelled', '2026-04-14 20:02:56', NULL, NULL, NULL);

-- --------------------------------------------------------

--
-- Table structure for table `order_items`
--

CREATE TABLE `order_items` (
  `order_item_id` int(11) NOT NULL,
  `order_id` int(11) NOT NULL,
  `seller_id` int(50) NOT NULL,
  `prod_id` int(11) NOT NULL,
  `quantity` int(11) DEFAULT NULL,
  `price` decimal(10,2) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `order_items`
--

INSERT INTO `order_items` (`order_item_id`, `order_id`, `seller_id`, `prod_id`, `quantity`, `price`) VALUES
(1, 1, 0, 1, 1, 500.00),
(2, 3, 0, 1, 1, 400.00),
(3, 4, 0, 1, 1, 660.00),
(4, 5, 0, 2, 2, 180.00),
(5, 6, 0, 3, 3, 180.00),
(6, 10, 0, 5, 1, 40.00),
(7, 11, 0, 3, 3, 180.00),
(8, 12, 0, 4, 2, 95.00),
(9, 13, 0, 2, 3, 90.00),
(10, 14, 0, 1, 2, 50.00),
(11, 15, 0, 1, 3, 50.00),
(12, 16, 0, 5, 1, 40.00),
(13, 17, 0, 3, 3, 180.00),
(14, 18, 0, 5, 1, 40.00),
(15, 19, 0, 2, 1, 90.00),
(16, 20, 0, 4, 1, 95.00),
(17, 21, 0, 3, 3, 180.00),
(18, 22, 0, 2, 1, 90.00),
(19, 23, 0, 2, 1, 90.00),
(20, 24, 0, 5, 1, 40.00),
(21, 25, 1, 5, 1, 40.00),
(22, 25, 3, 2, 1, 90.00),
(23, 26, 1, 3, 1, 180.00),
(24, 26, 3, 2, 1, 90.00),
(25, 27, 1, 1, 1, 50.00),
(26, 28, 1, 4, 2, 95.00),
(27, 29, 1, 3, 1, 180.00),
(28, 30, 1, 5, 1, 40.00),
(29, 31, 1, 3, 1, 180.00),
(30, 32, 1, 3, 1, 180.00),
(31, 33, 1, 4, 1, 95.00),
(32, 34, 3, 2, 1, 90.00),
(33, 35, 3, 2, 1, 90.00),
(34, 36, 1, 5, 1, 40.00),
(35, 37, 1, 4, 1, 95.00),
(36, 38, 1, 3, 1, 180.00),
(37, 39, 1, 5, 1, 40.00),
(38, 40, 3, 2, 1, 90.00),
(39, 40, 1, 5, 1, 40.00),
(40, 40, 1, 3, 1, 180.00),
(41, 41, 1, 3, 1, 180.00),
(42, 42, 1, 6, 1, 30.00),
(43, 43, 1, 3, 1, 180.00),
(44, 44, 1, 1, 3, 50.00),
(45, 45, 1, 1, 1, 50.00),
(46, 46, 1, 1, 1, 50.00),
(47, 47, 1, 1, 1, 50.00),
(48, 48, 1, 1, 1, 50.00),
(49, 49, 7, 14, 1, 50.00);

-- --------------------------------------------------------

--
-- Table structure for table `password_resets`
--

CREATE TABLE `password_resets` (
  `id` int(11) NOT NULL,
  `email` varchar(255) NOT NULL,
  `otp` varchar(6) NOT NULL,
  `reset_token` varchar(255) DEFAULT NULL,
  `is_verified` tinyint(1) DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `password_resets`
--

INSERT INTO `password_resets` (`id`, `email`, `otp`, `reset_token`, `is_verified`, `created_at`) VALUES
(1, 'rathodkaushik1002@gmail.com', '975945', 'ZwIHuorvbYPBK-YjpcvA0F6y1khF53qQoe6goMs53JE', 1, '2026-02-16 15:34:17'),
(15, 'kaushikrathod6110@gmail.com', '507894', 'FS00VwU5rej40IpZ7FC87FOlvAnuJ8wSlSoMdrBNj6c', 1, '2026-02-17 15:31:22');

-- --------------------------------------------------------

--
-- Table structure for table `payment`
--

CREATE TABLE `payment` (
  `payment_id` int(8) NOT NULL,
  `order_id` int(8) NOT NULL,
  `seller_id` int(5) NOT NULL,
  `delivery_staff_id` int(11) DEFAULT NULL,
  `payment_method` enum('Online','COD') NOT NULL,
  `payment_status` enum('Success','Pending','Failed') NOT NULL DEFAULT 'Pending',
  `transaction_id` varchar(255) NOT NULL,
  `payment_date` datetime NOT NULL,
  `amount` decimal(10,2) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `payment`
--

INSERT INTO `payment` (`payment_id`, `order_id`, `seller_id`, `delivery_staff_id`, `payment_method`, `payment_status`, `transaction_id`, `payment_date`, `amount`) VALUES
(7, 34, 3, 4, 'Online', 'Pending', 'ONLINE-34-20260411140640', '2026-04-11 14:06:40', 90.00),
(8, 35, 3, 4, 'Online', 'Success', 'pay_Sc7eRZx8gUmwQe', '2026-04-11 14:08:49', 90.00),
(9, 36, 1, 4, 'COD', 'Pending', 'COD-36-20260411140925', '2026-04-11 14:09:25', 40.00),
(10, 37, 1, NULL, 'Online', 'Success', 'pay_ScD7JRV8tCEtMd', '2026-04-11 19:29:18', 95.00),
(11, 38, 1, NULL, 'Online', 'Pending', 'ONLINE-38-20260411193243', '2026-04-11 19:32:43', 180.00),
(12, 39, 1, NULL, 'Online', 'Success', 'pay_ScETUuIS2Xz1e3', '2026-04-11 20:49:12', 40.00),
(13, 40, 3, NULL, 'COD', 'Pending', 'COD-40-20260411213719', '2026-04-11 21:37:19', 310.00),
(14, 41, 1, NULL, 'COD', 'Pending', 'COD-41-20260414121331', '2026-04-14 12:13:31', 207.00),
(15, 42, 1, NULL, 'Online', 'Pending', 'ONLINE-42-20260414122317', '2026-04-14 12:23:17', 57.00),
(16, 43, 1, NULL, 'Online', 'Pending', 'ONLINE-43-20260414123105', '2026-04-14 12:31:05', 207.00),
(17, 44, 1, NULL, 'COD', 'Pending', 'COD-44-20260414130004', '2026-04-14 13:00:04', 177.00),
(18, 45, 1, NULL, 'COD', 'Pending', 'COD-45-20260414135723', '2026-04-14 13:57:23', 77.00),
(19, 46, 1, NULL, 'COD', 'Pending', 'COD-46-20260414141207', '2026-04-14 14:12:07', 77.00),
(20, 47, 1, NULL, 'COD', 'Pending', 'COD-47-20260414142336', '2026-04-14 14:23:36', 77.00),
(21, 48, 1, NULL, 'COD', 'Pending', 'COD-48-20260414143326', '2026-04-14 14:33:26', 77.00),
(22, 49, 7, 2, 'Online', 'Success', 'pay_SdPH4oW4XgBtJc', '2026-04-14 20:01:46', 77.00);

-- --------------------------------------------------------

--
-- Table structure for table `product`
--

CREATE TABLE `product` (
  `prod_id` int(5) NOT NULL,
  `prod_name` varchar(50) NOT NULL,
  `category_id` int(5) NOT NULL,
  `brand` varchar(50) NOT NULL,
  `description` text NOT NULL,
  `prod_price` decimal(10,2) NOT NULL,
  `unit_type` varchar(30) NOT NULL,
  `stock_quantity` decimal(10,2) NOT NULL,
  `stock_status` enum('Available','Out of Stock') NOT NULL,
  `prod_image` varchar(255) NOT NULL,
  `prod_image2` varchar(255) DEFAULT NULL,
  `prod_image3` varchar(255) DEFAULT NULL,
  `expiry_at` datetime NOT NULL,
  `prod_status` enum('Active','Inactive') NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `product`
--

INSERT INTO `product` (`prod_id`, `prod_name`, `category_id`, `brand`, `description`, `prod_price`, `unit_type`, `stock_quantity`, `stock_status`, `prod_image`, `prod_image2`, `prod_image3`, `expiry_at`, `prod_status`) VALUES
(1, 'tomato', 2, 'K-Veg', 'Fresh & tasty Tomato', 50.00, 'kg', 5.00, 'Available', 'uploads/products/prod_1_7b64b87a00af425c88fcea3063e8a6ca.jpeg', NULL, NULL, '2026-03-02 19:10:26', 'Active'),
(2, 'coconut oil', 3, 'fortune', 'an edible, high-fat', 90.00, 'liter', 90.00, 'Available', 'uploads/products/prod_1_7a2f155c04a245aab2ec10f84c4f95a3.jpeg', NULL, NULL, '2026-03-21 16:12:29', 'Active'),
(3, 'Banana', 1, 'f-fresh', 'Good, healthy', 180.00, 'dozen', 76.00, 'Available', 'uploads/products/prod_1_06fbe14d6a7641d0aaa4633a49b50cbb.png', NULL, NULL, '2026-03-24 07:48:56', 'Active'),
(4, 'Coconut oil', 3, 'No Brand', 'Good Oil', 95.00, 'pcs', 213.00, 'Available', 'uploads/products/prod_1_6df4f0aaa7e4481fb1d53e82c5ff77f2.jpeg', 'uploads/products/prod_1_5e5ec9c8ce4e4b3a8a678fe8566b569f.jpeg', 'uploads/products/prod_1_7a2f155c04a245aab2ec10f84c4f95a3.jpeg', '2026-03-29 16:10:29', 'Active'),
(5, 'Carrot', 2, 'K-veg', 'Good & heathly Veg', 40.00, 'kg', 91.00, 'Available', 'uploads/products/prod_1_c28d2f56b3044e8aa3071d1a04e9e889.jpeg', NULL, NULL, '2026-03-29 16:45:27', 'Active'),
(6, 'bourbon biscuit', 4, 'Britannia', 'Tasty biscuits ', 30.00, 'pcs', 9.00, 'Available', 'uploads/products/prod_1_85f8a9761d4a4f5b844b92cebb76abe5.jpg', 'uploads/products/prod_1_76636b7a79a248a98d20bada84d2fa4d.jpg', 'uploads/products/prod_1_03657b29f0ef46e1891c0d78bd8270d6.jpg', '2026-04-13 12:36:55', 'Active'),
(7, 'Oreo biscuit', 4, 'Cadbury', 'Oreo is a popular sandwich cookie produced by Nabisco (a subsidiary of Mondelez International) featuring two crunchy, dark cocoa-based chocolate wafers filled with a sweet, creamy white center', 20.00, 'pcs', 100.00, 'Available', 'uploads/products/prod_1_4d6acb482e124b178c27718f67668d5b.webp', 'uploads/products/prod_1_e90583e0787e4d8597ddba883bf0813d.jpg', 'uploads/products/prod_1_3a0c8b1de2a44a1eaa774d3dc6248b7d.jpg', '2026-04-14 14:25:04', 'Active'),
(8, 'Hide & Seek Milano choco chip cookies', 4, 'Parle', 'Parle Hide & Seek Milano Choco Chip biscuits are premium, crunchy, and rich chocolate chip cookies from Parle’s Platina range.', 100.00, 'pcs', 50.00, 'Available', 'uploads/products/prod_1_622573995b7a4fc7a9a7f1a8367f08c2.png', 'uploads/products/prod_1_78df26e1b01a49329a1506aa06c4383f.png', 'uploads/products/prod_1_e2707caa80d2495983951ae2a5a7bef6.png', '2026-04-14 14:29:50', 'Active'),
(9, 'Dairy Milk', 9, 'Cadbury', 'Dairy milk is nutrient-rich liquid food produced by the mammary glands of mammals, most commonly cows, but also goats, sheep, and buffalo.', 20.00, 'pcs', 60.00, 'Available', 'uploads/products/prod_1_cddbc511a049440b965a4b941c5d3b31.jpg', 'uploads/products/prod_1_fa6f84a062904cc0bdc0828d5672f08b.jpg', 'uploads/products/prod_1_9f7071f1417d4fd7885ece472a170dbe.png', '2026-04-14 14:31:47', 'Active'),
(10, 'Kitkat', 9, 'Nestle', 'crispy, layered wafers coated in smooth milk chocolate', 40.00, 'pcs', 40.00, 'Available', 'uploads/products/prod_1_54042276df114d0ea1552b986ec26f48.png', 'uploads/products/prod_1_7b7ef3f4605f41fb9109432a9f7c9b38.png', 'uploads/products/prod_1_9ebce8a551424c83a218ac92de3db148.jpg', '2026-04-14 14:33:41', 'Active'),
(11, 'Dark fantasy choco fills', 4, 'Sunfeast', 'Sunfeast Dark Fantasy Choco Fills are premium cookies featuring a crunchy, baked, caramelized golden crust filled with rich, molten chocolate crème.', 100.00, 'pcs', 60.00, 'Available', 'uploads/products/prod_7_28f68330e9ac41ed9e19bffec3eb68a6.png', 'uploads/products/prod_7_f33aee0f68b04710ab87db6f5e68871c.jpg', 'uploads/products/prod_7_b87a8a6bfaa14f8da6308c24f9e678d8.png', '2026-04-14 14:39:19', 'Active'),
(12, 'Snickers', 9, 'Snickers', 'features a,Nougat center mixed with peanuts, topped with caramel, and coated in milk chocolate.', 20.00, 'pcs', 100.00, 'Available', 'uploads/products/prod_7_a8eafd63aa53474eb7ebd9d28f6f167d.png', 'uploads/products/prod_7_1857720c38de4cacb24316e85b4ab217.png', 'uploads/products/prod_7_a8674d524203426f9c18570d745aab84.jpg', '2026-04-14 14:41:24', 'Active'),
(13, 'Sprite', 8, 'Sprite', 'Sprite is a popular, caffeine-free, lemon-lime flavored soft drink owned by The Coca-Cola Company.', 30.00, 'pcs', 30.00, 'Available', 'uploads/products/prod_7_9631e7214829443d807061690b488b15.png', 'uploads/products/prod_7_886b4029e8d743248c46f891b253f21c.png', 'uploads/products/prod_7_0f8ba708453f40bc960abe260273d871.png', '2026-04-14 14:42:35', 'Active'),
(14, 'Coke diet', 8, 'Cocacola', 'Diet Coke is a sugar-free, zero-calorie soft drink produced by The Coca-Cola Company.', 50.00, 'pcs', 90.00, 'Available', 'uploads/products/prod_7_30a2977c101849b2aaa3f7846ba53c14.png', 'uploads/products/prod_7_d108ae242d924fd9903aa290659d76ef.png', NULL, '2026-04-14 14:43:50', 'Active'),
(15, 'Bread', 6, 'Bread', 'Bread is a staple food produced by baking a dough of flour (usually wheat) and water, commonly fermented with yeast, and seasoned with salt.', 50.00, 'pcs', 90.00, 'Available', 'uploads/products/prod_8_6b807fe8848e4b469e5f6202bf5233a1.png', 'uploads/products/prod_8_e0ce7bdc4b924e9c8cfcd11d6d3ff623.png', 'uploads/products/prod_8_a5fd3a15c515469da70da2f512dda1b6.png', '2026-04-14 14:46:55', 'Active'),
(16, 'Chocolate muffins', 6, 'Muffins', 'Chocolate muffins are rich, moist, and indulgent baked goods characterized by an intense cocoa flavor, often featuring a deep brown crumb, a soft texture, and loaded with chocolate chips.', 50.00, 'gm', 90.00, 'Available', 'uploads/products/prod_8_5957441dcdda45a999737c94d7eda6ea.png', NULL, NULL, '2026-04-14 14:48:30', 'Active'),
(17, 'Chocolate pastry', 6, 'Choco', 'Pastry is a versatile baked dough made primarily from flour, fat (butter, lard), and liquid (water, milk), often yielding a light, flaky, or crisp texture.', 150.00, 'gm', 150.00, 'Available', 'uploads/products/prod_8_530f29963a6e4048af87b4df951aa2d9.png', 'uploads/products/prod_8_d9c98fd2e818478790b15633784b649b.png', 'uploads/products/prod_8_fdbad52b8fb24e77a2ee9681afdf9d58.png', '2026-04-14 14:50:11', 'Active'),
(18, 'Butter', 6, 'Amul', 'Amul butter is a popular, hygienic, and convenient cottage cheese brand known for its soft, smooth, and uniform texture.', 800.00, 'kg', 50.00, 'Available', 'uploads/products/prod_8_bd1520c23d5640c5a74a4fb7f265ae96.png', 'uploads/products/prod_8_39333b7d4c78473a982dfa8fdf4da63d.png', 'uploads/products/prod_8_2cf78fa5cb18424ea513426ab042fa7c.png', '2026-04-14 14:52:17', 'Active'),
(19, 'Red Chilli Powder', 5, 'Nithin Spices', 'Agmark graded, hygienic, and flavorful', 95.00, 'pcs', 70.00, 'Available', 'uploads/products/prod_5_d99feae0937a4deeb5838522f7356ff5.jpg', 'uploads/products/prod_5_aa485c5fe7ad47a580e1c41d8099ce70.jpg', 'uploads/products/prod_5_bbef54eb6ec7474aa649278e4e675d18.jpg', '2026-04-14 20:14:11', 'Active');

-- --------------------------------------------------------

--
-- Table structure for table `product_reviews`
--

CREATE TABLE `product_reviews` (
  `review_id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `prod_id` int(11) NOT NULL,
  `seller_id` int(11) DEFAULT NULL,
  `rating` int(11) NOT NULL CHECK (`rating` between 1 and 5),
  `review` text DEFAULT NULL,
  `created_at` datetime DEFAULT current_timestamp(),
  `updated_at` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `product_reviews`
--

INSERT INTO `product_reviews` (`review_id`, `user_id`, `prod_id`, `seller_id`, `rating`, `review`, `created_at`, `updated_at`) VALUES
(1, 1, 5, 1, 4, 'best & healthy', '2026-04-08 18:48:53', '2026-04-10 11:41:33'),
(2, 2, 3, 1, 3, 'good', '2026-04-09 23:47:21', '2026-04-09 23:47:21'),
(3, 1, 2, 3, 5, 'best oil 👍', '2026-04-10 20:34:02', '2026-04-10 20:34:02');

-- --------------------------------------------------------

--
-- Table structure for table `product_seller`
--

CREATE TABLE `product_seller` (
  `ps_id` int(5) NOT NULL,
  `prod_id` int(5) NOT NULL,
  `seller_id` int(5) NOT NULL,
  `stock_qty` decimal(10,2) NOT NULL,
  `selling_price` decimal(10,2) NOT NULL,
  `ps_status` enum('Active','Inactive') NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `product_seller`
--

INSERT INTO `product_seller` (`ps_id`, `prod_id`, `seller_id`, `stock_qty`, `selling_price`, `ps_status`) VALUES
(1, 1, 1, 5.00, 50.00, 'Active'),
(2, 2, 3, 90.00, 90.00, 'Active'),
(3, 3, 1, 76.00, 180.00, 'Active'),
(5, 4, 1, 213.00, 95.00, 'Active'),
(6, 5, 1, 91.00, 40.00, 'Active'),
(7, 6, 1, 9.00, 30.00, 'Active'),
(8, 7, 1, 100.00, 20.00, 'Active'),
(9, 8, 1, 50.00, 100.00, 'Active'),
(10, 9, 1, 60.00, 20.00, 'Active'),
(11, 10, 1, 40.00, 40.00, 'Active'),
(12, 11, 7, 60.00, 100.00, 'Active'),
(13, 12, 7, 100.00, 20.00, 'Active'),
(14, 13, 7, 30.00, 30.00, 'Active'),
(15, 14, 7, 90.00, 50.00, 'Active'),
(16, 15, 8, 90.00, 50.00, 'Active'),
(17, 16, 8, 90.00, 50.00, 'Active'),
(18, 17, 8, 150.00, 150.00, 'Active'),
(19, 18, 8, 50.00, 800.00, 'Active'),
(20, 19, 5, 70.00, 95.00, 'Active');

-- --------------------------------------------------------

--
-- Table structure for table `seller`
--

CREATE TABLE `seller` (
  `seller_id` int(11) NOT NULL,
  `seller_name` varchar(50) NOT NULL,
  `seller_email` varchar(50) NOT NULL,
  `seller_mobile` bigint(10) NOT NULL,
  `shop_address` varchar(200) NOT NULL,
  `shop_name` varchar(50) NOT NULL,
  `seller_pass` varchar(200) NOT NULL,
  `store_logo` varchar(200) DEFAULT NULL,
  `registration_date` datetime NOT NULL DEFAULT current_timestamp(),
  `pincode` bigint(6) DEFAULT NULL,
  `licence_no` varchar(255) DEFAULT NULL,
  `status` enum('active','inactive') NOT NULL DEFAULT 'active',
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `seller`
--

INSERT INTO `seller` (`seller_id`, `seller_name`, `seller_email`, `seller_mobile`, `shop_address`, `shop_name`, `seller_pass`, `store_logo`, `registration_date`, `pincode`, `licence_no`, `status`, `updated_at`) VALUES
(1, 'mahipal rajput', 'mahi0656@gmail.com', 7896541230, 'nava vadaj', 'mahi_love', '$2b$12$mD9Jrv2Aw3Dh/LsYRY5jw.V9FQZaZJLtv05XXofayFn4NY3rSA7/C', 'seller_1_236c53f1a8304bb385b648e888b42bec.jpg', '2025-12-10 20:27:51', NULL, NULL, 'active', '2026-04-12 17:58:10'),
(3, 'priti', 'pritirathod0707@gmail.com', 7434076639, 'Maninagar', 'priti\'s shop', '$2b$12$1m.4x73no37.HooMndRcbucVUy101mWMmpUCFTRShDphRb/ZfFYX2', NULL, '0000-00-00 00:00:00', NULL, NULL, 'active', '2026-03-02 20:02:43'),
(4, 'ani rathod', 'ani01@gmail.com', 9106257143, 'amraiwadi', 'Ani\'s shop', '$2b$12$eBejkUWuGAHP86D.i1IyaunfXe6MsRv1FptOjukN273/e6OpNwLuW', 'seller_4_0f6517ead2af40d6b87009b5d52638d5.jpg', '2026-03-02 20:25:27', NULL, NULL, 'active', '2026-04-12 18:03:57'),
(5, 'dev vaghela', 'dev006@gmail.com', 5588002255, 'shop-22, radhe complex,rabari colony', 'Dev\'s shop', '$2b$12$jbQsa6e695AWkWaEXjdSG.yE9eg30b53f7.PQA78CNsU2zoJFMoc6', NULL, '2026-04-07 11:48:52', 380001, NULL, 'active', '2026-04-07 23:55:44'),
(6, 'vinod yogi', 'vinod18@gmail.com', 1144773366, 'shop-199,krishnanagar', 'new ramdev shop', '$2b$12$KbOVqcr2kmutidWwjflacen73Y7OXnPbnxMmKoHVOv.VmD/lJBX0a', 'seller_6_a09e9cdaae044e62b9ac291120463323.png', '2026-04-07 12:16:38', NULL, NULL, 'active', '2026-04-12 18:02:05'),
(7, 'Piyush Rawat', 'piyush30@gmail.com', 7848586898, '32, shahpur', 'Shree Ram shop', '$2b$12$/5OoBrYrk0DzpYDd2wZQBu1RnAyE15eSOaM0TUxnx4JBAbBCWyMDO', 'seller_7_e4d4c6b36d7049fb943d22a7f3447cd0.png', '2026-04-12 18:14:52', 380808, NULL, 'active', '2026-04-12 18:15:26'),
(8, 'Vivek Solanki', 'vivek4455@gmail.com', 2233552233, 'shop-16, gomtipur', 'vivek\'s shop', '$2b$12$F.uutafu07XbP3mss7rP8O.Zd22HEnmKETudsOCsejpUojTN/XPke', NULL, '2026-04-12 18:17:15', NULL, NULL, 'active', '2026-04-12 18:17:15'),
(9, 'pavan shinde', 'pavan07@gmail.com', 4554566556, '54, amraiwadi', 'pavan\'s shop', '$2b$12$9yQxZcLjOvUPuUsdOGQc6u4gi4iJlyAorbsporeX1fkFfeEIp7.hG', 'seller_9_9d7280b7c6404cae8763e8c8245ca41a.png', '2026-04-12 18:34:09', NULL, NULL, 'active', '2026-04-12 18:34:31');

-- --------------------------------------------------------

--
-- Table structure for table `user`
--

CREATE TABLE `user` (
  `user_id` int(11) NOT NULL,
  `user_name` varchar(50) NOT NULL,
  `user_email` varchar(50) NOT NULL,
  `user_mobile` bigint(10) NOT NULL,
  `user_address` varchar(200) NOT NULL,
  `user_pass` varchar(200) NOT NULL,
  `pincode` bigint(6) DEFAULT NULL,
  `status` enum('active','inactive') NOT NULL DEFAULT 'active',
  `profile_image` varchar(255) DEFAULT NULL,
  `registration_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `user`
--

INSERT INTO `user` (`user_id`, `user_name`, `user_email`, `user_mobile`, `user_address`, `user_pass`, `pincode`, `status`, `profile_image`, `registration_at`, `updated_at`) VALUES
(1, 'kashish agrawal', 'kashish01@gmail.com', 1478520369, 'amraiwadi', '$2b$12$qKNKYFR4S1ds/P1mhfIcx.FNnCIuV67jk1Ppp5kEfo2ahrLUG2grK', 380001, 'active', 'user_1_91a0e9428b.jpg', '2026-03-02 22:26:23', '2026-04-07 12:22:09'),
(2, 'krishiv rathor', 'krishu123@gmail.com', 1020304050, 'nikol', '$2b$12$qATndeAYY4TamAd1qv.D8.2C5FpArtsf344exAYtg0nAPqStfv33C', 380020, 'active', 'user_2_8bbfe09705.jpg', '2026-03-02 22:26:23', '2026-04-12 17:55:27'),
(3, 'xxx', 'fhg@gmaul.com', 1227474741, 'ghwdjfk', '$2b$12$TUahnJ3y1zY/u0nDfpQIYeYThCIJeqfJk1WAOQx7bYGYt9DbZdUXa', NULL, 'inactive', NULL, '2026-03-02 22:26:23', '2026-03-28 11:58:01'),
(4, 'asdf', 'sff@ghk.com', 9999999999, 'gomtipur', '$2b$12$I31bMZLeDIgfQ2NUAk98vuWmt0u3V3BSNRJJL6NxXNvundRF8rel6', NULL, 'inactive', NULL, '2026-03-02 22:26:23', '2026-03-28 11:58:26'),
(6, 'harshraj rathor', 'harshrajrathor4@gmail.com', 7990254581, 'krishananagar', '$2b$12$0lyMwf0VW7wfcYhT8D7GPecKDQwVE4LCq04eOcA.45ehQAOj8Y90O', NULL, 'active', NULL, '2026-03-02 22:26:23', '2026-03-28 11:58:35'),
(7, 'HIMANI SAGAR', 'hnsagar.2805@gmail.com', 7874171106, 'maninagar', '$2b$12$6Z0yqPmM6RHg2Z3t0ejFLOSRo7tJYJYJX94LY.CELUH0hc6At/tpS', NULL, 'active', NULL, '2026-03-02 22:26:23', '2026-03-28 11:58:44'),
(8, 'divya rathod', 'divya014@gmail.com', 7574812490, 'gomtipur', '$2b$12$vYyr61.pM6U5RT50qYsvX.mbmrOJWIA2f2IZr/.kAS2ULEnsZvS0y', 380040, 'active', NULL, '2026-03-02 23:13:15', '2026-04-09 20:17:46'),
(9, 'mayur makwana', 'mayur1805@gmail.com', 8080909010, 'amraiwadi', '$2b$12$B3YGBJ126FPH/ymnE8eVkeLvNARqRjrxh11oEnqPEsK0gxdjIIFJq', 385050, 'active', NULL, '2026-04-11 21:35:07', '2026-04-14 14:14:58'),
(10, 'Kiran Rathod', 'kiran1011@gmail.com', 1223345667, '24/226, manhar nagar society, gomtipur', '$2b$12$lcLHNibveBFS.xj64OXUXOXTFfF29jaWVWjjZRfly0pUdAwJYE1RS', 380021, 'active', NULL, '2026-04-14 19:58:26', '2026-04-14 20:00:51');

-- --------------------------------------------------------

--
-- Table structure for table `wishlist`
--

CREATE TABLE `wishlist` (
  `wishlist_id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `prod_id` int(11) NOT NULL,
  `seller_id` int(11) NOT NULL DEFAULT 0,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `wishlist`
--

INSERT INTO `wishlist` (`wishlist_id`, `user_id`, `prod_id`, `seller_id`, `created_at`, `updated_at`) VALUES
(2, 1, 1, 1, '2026-04-10 00:37:26', '2026-04-10 00:37:26'),
(3, 2, 3, 1, '2026-04-11 14:06:24', '2026-04-11 14:06:24'),
(4, 8, 4, 1, '2026-04-11 19:27:36', '2026-04-11 19:27:36'),
(7, 1, 2, 3, '2026-04-12 18:05:06', '2026-04-12 18:05:06'),
(8, 1, 4, 1, '2026-04-12 18:05:09', '2026-04-12 18:05:09');

--
-- Indexes for dumped tables
--

--
-- Indexes for table `admin`
--
ALTER TABLE `admin`
  ADD PRIMARY KEY (`admin_id`),
  ADD UNIQUE KEY `admin_email` (`admin_email`),
  ADD UNIQUE KEY `admin_pass` (`admin_pass`);

--
-- Indexes for table `admin_notifications`
--
ALTER TABLE `admin_notifications`
  ADD PRIMARY KEY (`notification_id`);

--
-- Indexes for table `app_feedback`
--
ALTER TABLE `app_feedback`
  ADD PRIMARY KEY (`feedback_id`);

--
-- Indexes for table `block_requests`
--
ALTER TABLE `block_requests`
  ADD PRIMARY KEY (`request_id`),
  ADD KEY `idx_block_requests_lookup` (`account_type`,`account_id`,`request_status`),
  ADD KEY `idx_block_requests_email` (`email`);

--
-- Indexes for table `cart`
--
ALTER TABLE `cart`
  ADD PRIMARY KEY (`cart_id`),
  ADD KEY `fk_user` (`user_id`),
  ADD KEY `fk_product` (`prod_id`),
  ADD KEY `fk_seller4` (`seller_id`);

--
-- Indexes for table `category`
--
ALTER TABLE `category`
  ADD PRIMARY KEY (`category_id`),
  ADD UNIQUE KEY `category_name` (`category_name`);

--
-- Indexes for table `delivery`
--
ALTER TABLE `delivery`
  ADD PRIMARY KEY (`delivery_id`),
  ADD KEY `fk_order1` (`order_id`),
  ADD KEY `fk_ds2` (`delivery_staff_id`);

--
-- Indexes for table `delivery_staff`
--
ALTER TABLE `delivery_staff`
  ADD PRIMARY KEY (`delivery_staff_id`),
  ADD UNIQUE KEY `d_s_mobile` (`d_s_mobile`,`d_s_email`,`d_s_pass`),
  ADD UNIQUE KEY `staff_licence_no` (`staff_licence_no`);

--
-- Indexes for table `delivery_staff_reviews`
--
ALTER TABLE `delivery_staff_reviews`
  ADD PRIMARY KEY (`delivery_review_id`),
  ADD UNIQUE KEY `uq_delivery_staff_review_order_user` (`order_id`,`user_id`),
  ADD KEY `idx_delivery_staff_reviews_staff` (`delivery_staff_id`),
  ADD KEY `idx_delivery_staff_reviews_user` (`user_id`),
  ADD KEY `idx_delivery_staff_reviews_order` (`order_id`);

--
-- Indexes for table `orders`
--
ALTER TABLE `orders`
  ADD PRIMARY KEY (`order_id`),
  ADD KEY `fk_seller1` (`seller_id`),
  ADD KEY `fk_cart` (`cart_id`),
  ADD KEY `fk_user1` (`user_id`),
  ADD KEY `fk_orders_delivery_staff` (`delivery_staff_id`);

--
-- Indexes for table `order_items`
--
ALTER TABLE `order_items`
  ADD PRIMARY KEY (`order_item_id`),
  ADD KEY `order_id` (`order_id`),
  ADD KEY `prod_id` (`prod_id`);

--
-- Indexes for table `password_resets`
--
ALTER TABLE `password_resets`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `payment`
--
ALTER TABLE `payment`
  ADD PRIMARY KEY (`payment_id`),
  ADD KEY `fk_order` (`order_id`),
  ADD KEY `fk_seller2` (`seller_id`),
  ADD KEY `fk_ds1` (`delivery_staff_id`),
  ADD KEY `idx_payment_order_id` (`order_id`);

--
-- Indexes for table `product`
--
ALTER TABLE `product`
  ADD PRIMARY KEY (`prod_id`),
  ADD KEY `fk_category` (`category_id`);

--
-- Indexes for table `product_reviews`
--
ALTER TABLE `product_reviews`
  ADD PRIMARY KEY (`review_id`),
  ADD UNIQUE KEY `uq_user_product_seller_review` (`user_id`,`prod_id`,`seller_id`);

--
-- Indexes for table `product_seller`
--
ALTER TABLE `product_seller`
  ADD PRIMARY KEY (`ps_id`),
  ADD KEY `fk_seller` (`seller_id`),
  ADD KEY `fk_prod` (`prod_id`);

--
-- Indexes for table `seller`
--
ALTER TABLE `seller`
  ADD PRIMARY KEY (`seller_id`),
  ADD UNIQUE KEY `seller_email` (`seller_email`,`seller_mobile`,`seller_pass`),
  ADD UNIQUE KEY `uq_seller_email` (`seller_email`),
  ADD UNIQUE KEY `uq_seller_mobile` (`seller_mobile`),
  ADD UNIQUE KEY `licence_no` (`licence_no`);

--
-- Indexes for table `user`
--
ALTER TABLE `user`
  ADD PRIMARY KEY (`user_id`),
  ADD UNIQUE KEY `user_email` (`user_email`,`user_mobile`,`user_pass`);

--
-- Indexes for table `wishlist`
--
ALTER TABLE `wishlist`
  ADD PRIMARY KEY (`wishlist_id`),
  ADD UNIQUE KEY `uq_wishlist_user_product_seller` (`user_id`,`prod_id`,`seller_id`),
  ADD KEY `idx_wishlist_user` (`user_id`),
  ADD KEY `idx_wishlist_product` (`prod_id`,`seller_id`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `admin_notifications`
--
ALTER TABLE `admin_notifications`
  MODIFY `notification_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `app_feedback`
--
ALTER TABLE `app_feedback`
  MODIFY `feedback_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `block_requests`
--
ALTER TABLE `block_requests`
  MODIFY `request_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `cart`
--
ALTER TABLE `cart`
  MODIFY `cart_id` int(5) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=65;

--
-- AUTO_INCREMENT for table `category`
--
ALTER TABLE `category`
  MODIFY `category_id` int(5) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=11;

--
-- AUTO_INCREMENT for table `delivery`
--
ALTER TABLE `delivery`
  MODIFY `delivery_id` int(8) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=20;

--
-- AUTO_INCREMENT for table `delivery_staff`
--
ALTER TABLE `delivery_staff`
  MODIFY `delivery_staff_id` int(5) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT for table `delivery_staff_reviews`
--
ALTER TABLE `delivery_staff_reviews`
  MODIFY `delivery_review_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `orders`
--
ALTER TABLE `orders`
  MODIFY `order_id` int(8) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=50;

--
-- AUTO_INCREMENT for table `order_items`
--
ALTER TABLE `order_items`
  MODIFY `order_item_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=50;

--
-- AUTO_INCREMENT for table `password_resets`
--
ALTER TABLE `password_resets`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=17;

--
-- AUTO_INCREMENT for table `payment`
--
ALTER TABLE `payment`
  MODIFY `payment_id` int(8) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=23;

--
-- AUTO_INCREMENT for table `product`
--
ALTER TABLE `product`
  MODIFY `prod_id` int(5) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=20;

--
-- AUTO_INCREMENT for table `product_reviews`
--
ALTER TABLE `product_reviews`
  MODIFY `review_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `product_seller`
--
ALTER TABLE `product_seller`
  MODIFY `ps_id` int(5) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=21;

--
-- AUTO_INCREMENT for table `seller`
--
ALTER TABLE `seller`
  MODIFY `seller_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=10;

--
-- AUTO_INCREMENT for table `user`
--
ALTER TABLE `user`
  MODIFY `user_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=11;

--
-- AUTO_INCREMENT for table `wishlist`
--
ALTER TABLE `wishlist`
  MODIFY `wishlist_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=9;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `cart`
--
ALTER TABLE `cart`
  ADD CONSTRAINT `fk_product` FOREIGN KEY (`prod_id`) REFERENCES `product` (`prod_id`),
  ADD CONSTRAINT `fk_seller4` FOREIGN KEY (`seller_id`) REFERENCES `seller` (`seller_id`),
  ADD CONSTRAINT `fk_user` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`);

--
-- Constraints for table `delivery`
--
ALTER TABLE `delivery`
  ADD CONSTRAINT `fk_ds2` FOREIGN KEY (`delivery_staff_id`) REFERENCES `delivery_staff` (`delivery_staff_id`),
  ADD CONSTRAINT `fk_order1` FOREIGN KEY (`order_id`) REFERENCES `orders` (`order_id`);

--
-- Constraints for table `orders`
--
ALTER TABLE `orders`
  ADD CONSTRAINT `fk_cart` FOREIGN KEY (`cart_id`) REFERENCES `cart` (`cart_id`),
  ADD CONSTRAINT `fk_ds` FOREIGN KEY (`delivery_staff_id`) REFERENCES `delivery_staff` (`delivery_staff_id`),
  ADD CONSTRAINT `fk_orders_delivery_staff` FOREIGN KEY (`delivery_staff_id`) REFERENCES `delivery_staff` (`delivery_staff_id`),
  ADD CONSTRAINT `fk_seller1` FOREIGN KEY (`seller_id`) REFERENCES `seller` (`seller_id`),
  ADD CONSTRAINT `fk_user1` FOREIGN KEY (`user_id`) REFERENCES `user` (`user_id`);

--
-- Constraints for table `order_items`
--
ALTER TABLE `order_items`
  ADD CONSTRAINT `order_items_ibfk_1` FOREIGN KEY (`order_id`) REFERENCES `orders` (`order_id`) ON DELETE CASCADE,
  ADD CONSTRAINT `order_items_ibfk_2` FOREIGN KEY (`prod_id`) REFERENCES `product` (`prod_id`) ON DELETE CASCADE;

--
-- Constraints for table `payment`
--
ALTER TABLE `payment`
  ADD CONSTRAINT `fk_ds1` FOREIGN KEY (`delivery_staff_id`) REFERENCES `delivery_staff` (`delivery_staff_id`),
  ADD CONSTRAINT `fk_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`order_id`),
  ADD CONSTRAINT `fk_seller2` FOREIGN KEY (`seller_id`) REFERENCES `seller` (`seller_id`);

--
-- Constraints for table `product`
--
ALTER TABLE `product`
  ADD CONSTRAINT `fk_category` FOREIGN KEY (`category_id`) REFERENCES `category` (`category_id`);

--
-- Constraints for table `product_seller`
--
ALTER TABLE `product_seller`
  ADD CONSTRAINT `fk_prod` FOREIGN KEY (`prod_id`) REFERENCES `product` (`prod_id`),
  ADD CONSTRAINT `fk_seller` FOREIGN KEY (`seller_id`) REFERENCES `seller` (`seller_id`);
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
