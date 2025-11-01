WITH patient_icu_stays AS (
    SELECT 
        p.subject_id,
        i.stay_id,
        i.intime,
        i.outtime,
        (p.anchor_year - p.anchor_age) AS birth_year,
        EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age) AS age_at_icu
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON i.subject_id = p.subject_id
    WHERE p.gender = 'M'
      AND i.intime IS NOT NULL
      AND i.outtime IS NOT NULL
      AND p.anchor_year IS NOT NULL
      AND p.anchor_age IS NOT NULL
),
first_icu_stays AS (
    SELECT 
        subject_id,
        stay_id,
        intime,
        outtime,
        age_at_icu
    FROM (
        SELECT 
            *,
            ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
        FROM patient_icu_stays
        WHERE age_at_icu BETWEEN 62 AND 72
    )
    WHERE rn = 1
),
spo2_measurements AS (
    SELECT 
        f.subject_id,
        f.stay_id,
        f.intime,
        f.outtime,
        f.age_at_icu,
        c.charttime,
        c.valuenum AS spo2_value
    FROM first_icu_stays f
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c 
        ON f.stay_id = c.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` d 
        ON c.itemid = d.itemid
        AND d.category = 'Vitals'
        AND d.label LIKE '%SpO2%'
    WHERE c.charttime BETWEEN f.intime AND f.outtime
      AND c.valuenum IS NOT NULL
      AND c.valuenum BETWEEN 0 AND 100
),
first_spo2_per_stay AS (
    SELECT 
        spo2_value
    FROM (
        SELECT 
            *,
            ROW_NUMBER() OVER (PARTITION BY stay_id ORDER BY charttime) AS rn
        FROM spo2_measurements
    )
    WHERE rn = 1
)
SELECT 
    APPROX_QUANTILES(spo2_value, 4)[SAFE_OFFSET(3)] - APPROX_QUANTILES(spo2_value, 4)[SAFE_OFFSET(1)] AS iqr
FROM first_spo2_per_stay;