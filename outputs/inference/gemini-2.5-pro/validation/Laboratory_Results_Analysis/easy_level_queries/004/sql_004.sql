WITH SepsisAdmissions AS (
    -- First, identify all hospital admissions (hadm_id) with a sepsis diagnosis.
    -- This is done by searching for 'sepsis' in the long title of the diagnosis codes.
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` USING (icd_code, icd_version)
    WHERE LOWER(long_title) LIKE '%sepsis%'
),

PatientCohort AS (
    -- Next, define the specific cohort of "similar patients":
    -- females, aged 71-81, who have a sepsis-related admission.
    SELECT
        p.subject_id,
        a.hadm_id,
        a.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON p.subject_id = a.subject_id
    -- Join with our sepsis admissions to filter for the correct diagnosis
    JOIN SepsisAdmissions AS s ON a.hadm_id = s.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 71 AND 81 -- A 10-year window around the specified age of 76
),

First24hAvgPlatelets AS (
    -- For each patient in the cohort, calculate their average platelet count
    -- using only measurements from the first 24 hours of their hospital stay.
    SELECT
        cohort.hadm_id,
        AVG(le.valuenum) AS avg_platelet_count
    FROM PatientCohort AS cohort
    -- Join with lab events to get platelet measurements
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le ON cohort.hadm_id = le.hadm_id
    WHERE
        -- Filter for Platelet Count (itemid 51265)
        le.itemid = 51265
        -- Ensure the measurement has a valid numeric value
        AND le.valuenum IS NOT NULL
        -- Filter for measurements taken within the first 24 hours of admission
        AND le.charttime BETWEEN cohort.admittime AND DATETIME_ADD(cohort.admittime, INTERVAL 24 HOUR)
    GROUP BY
        cohort.hadm_id
)

-- Finally, calculate the median of the per-patient average platelet counts.
SELECT
    -- Using APPROX_QUANTILES to find the median (the 2nd quantile)
    -- is a standard and efficient method in BigQuery.
    APPROX_QUANTILES(avg_platelet_count, 2)[OFFSET(1)] AS median_platelet_count_k_ul
FROM First24hAvgPlatelets;