WITH cohort AS (
    SELECT 
        i.stay_id,
        i.subject_id,
        i.hadm_id,
        i.intime,
        i.outtime,
        p.gender,
        -- Compute birth date: anchor_year is the year of the anchor event, anchor_age is the age at that time
        DATE_SUB(DATE(p.anchor_year, 1, 1), INTERVAL p.anchor_age YEAR) AS birth_date,
        -- Compute age at ICU admission (intime)
        DATE_DIFF(i.intime, DATE_SUB(DATE(p.anchor_year, 1, 1), INTERVAL p.anchor_age YEAR), YEAR) AS age_at_intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON i.subject_id = p.subject_id
    WHERE p.gender = 'F'
        AND DATE_DIFF(i.intime, DATE_SUB(DATE(p.anchor_year, 1, 1), INTERVAL p.anchor_age YEAR), YEAR) BETWEEN 38 AND 48
),
spo2_measurements AS (
    SELECT 
        c.stay_id,
        ce.valuenum
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON c.subject_id = ce.subject_id
        AND c.hadm_id = ce.hadm_id
        AND c.stay_id = ce.stay_id
        AND ce.itemid = 220045  -- SpO2 percentage
        AND ce.charttime BETWEEN c.intime AND c.outtime
        AND ce.valuenum BETWEEN 0 AND 100  -- Valid SpO2 range
),
mean_spo2_per_stay AS (
    SELECT 
        stay_id,
        AVG(valuenum) AS mean_spo2
    FROM spo2_measurements
    GROUP BY stay_id
)
SELECT 
    COUNTIF(mean_spo2 <= 92) / COUNT(*) AS proportion
FROM mean_spo2_per_stay;