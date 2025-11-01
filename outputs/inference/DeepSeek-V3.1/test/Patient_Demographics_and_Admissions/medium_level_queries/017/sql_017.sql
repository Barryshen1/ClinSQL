WITH first_icustay AS (
    SELECT 
        icu.subject_id,
        icu.hadm_id,
        icu.stay_id,
        icu.los,
        ROW_NUMBER() OVER (PARTITION BY icu.hadm_id ORDER BY icu.intime) AS stay_rank
    FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
),
cohort AS (
    SELECT 
        p.subject_id,
        p.gender,
        p.anchor_age,
        a.hadm_id,
        a.discharge_location,
        a.hospital_expire_flag,
        icu.los
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN first_icustay icu
        ON a.hadm_id = icu.hadm_id AND icu.stay_rank = 1
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 38 AND 48
),
discharge_categories AS (
    SELECT 
        *,
        CASE 
            WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
            WHEN discharge_location = 'HOME' THEN 'Home'
            ELSE 'Facility'
        END AS discharge_category
    FROM cohort
)
SELECT 
    discharge_category,
    COUNT(*) AS n_stays,
    AVG(los) AS mean_los,
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS p50_los,
    APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los,
    APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los
FROM discharge_categories
GROUP BY discharge_category
ORDER BY discharge_category;