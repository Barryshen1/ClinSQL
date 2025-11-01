WITH patient_admissions AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.discharge_location,
        a.hospital_expire_flag,
        -- Compute age at admission in years using valid TIMESTAMP function
        TIMESTAMP_DIFF(TIMESTAMP(a.admittime), TIMESTAMP(CONCAT(CAST(p.anchor_year - p.anchor_age AS STRING), '-01-01')), YEAR) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_year IS NOT NULL
      AND p.anchor_age IS NOT NULL
      AND a.dischtime IS NOT NULL  -- Ensure dischtime is not null for LOS calculation
),
filtered_admissions AS (
    SELECT 
        pa.*,
        -- Create discharge category
        CASE 
            WHEN pa.hospital_expire_flag = 1 THEN 'In-Hospital Mortality'
            WHEN pa.discharge_location LIKE '%Hospice%' THEN 'Discharged to Hospice'
            WHEN pa.discharge_location = 'Home' THEN 'Discharged Home'
            ELSE 'Other'
        END AS discharge_category
    FROM patient_admissions pa
    -- Exclude ICU stays
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
        ON pa.hadm_id = i.hadm_id
    WHERE i.hadm_id IS NULL   -- no ICU stay
      AND pa.age_at_admission BETWEEN 75 AND 85
      AND discharge_category IN ('In-Hospital Mortality', 'Discharged to Hospice', 'Discharged Home')
)
SELECT 
    discharge_category,
    AVG(DATEDIFF(dischtime, admittime)) AS mean_los,
    STDDEV(DATEDIFF(dischtime, admittime)) AS std_los
FROM filtered_admissions
GROUP BY discharge_category
ORDER BY discharge_category;