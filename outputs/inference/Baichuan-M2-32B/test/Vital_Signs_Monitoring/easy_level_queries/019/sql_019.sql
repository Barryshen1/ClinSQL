SELECT DISTINCT first_careunit, last_careunit 
FROM `physionet-data.mimiciv_3_1_icu.icustays`
WHERE first_careunit LIKE '%Step%' OR last_careunit LIKE '%Step%';