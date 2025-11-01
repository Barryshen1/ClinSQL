WITH cohort AS (
    SELECT 
        p.subject_id, 
        p.anchor_age,
        i.hadm_id, 
        i.stay_id,
        i.intime,
        i.outtime,
        i.los AS icu_los,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON i.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON i.hadm_id = a.hadm_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 88 AND 98
        AND i.hadm_id IN (
            SELECT hadm_id 
            FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` 
            WHERE icd_code LIKE '5A1D%' OR icd_code = 'Z99.2'
        )
),

lactate_first72h AS (
    SELECT 
        c.stay_id,
        MAX(l.valuenum) AS max_lactate
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
        ON c.hadm_id = l.hadm_id
    WHERE l.itemid = 50813  -- lactate
        AND l.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    GROUP BY c.stay_id
),

cohort_with_lactate AS (
    SELECT 
        c.*,
        l.max_lactate
    FROM cohort c
    INNER JOIN lactate_first72h l
        ON c.stay_id = l.stay_id
),

percentile_info AS (
    SELECT 
        APPROX_QUANTILES(max_lactate, 100) AS percentiles
    FROM cohort_with_lactate
),

percentile_of_85 AS (
    SELECT 
        (SELECT MAX(offset) 
         FROM UNNEST(percentiles) AS p WITH OFFSET 
         WHERE p <= 85) AS percentile
    FROM percentile_info
),

quartile_threshold AS (
    SELECT 
        APPROX_QUANTILES(max_lactate, 4)[OFFSET(3)] AS q3_threshold
    FROM cohort_with_lactate
),

most_unstable AS (
    SELECT 
        stay_id,
        icu_los,
        hospital_expire_flag
    FROM cohort_with_lactate
    WHERE max_lactate >= (SELECT q3_threshold FROM quartile_threshold)
)

SELECT 
    (SELECT percentile FROM percentile_of_85) AS percentile_of_85,
    (SELECT APPROX_QUANTILES(icu_los, 100)[OFFSET(50)] FROM most_unstable) AS median_icu_los_q3,
    (SELECT COUNT(*) FROM most_unstable WHERE hospital_expire_flag = 1) * 100.0 / 
        (SELECT COUNT(*) FROM most_unstable) AS hospital_mortality_percent_q3;