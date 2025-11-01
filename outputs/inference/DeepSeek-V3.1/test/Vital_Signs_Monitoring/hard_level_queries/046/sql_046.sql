WITH stroke_cohort AS (
    SELECT 
        p.subject_id, 
        p.gender, 
        p.anchor_age,
        i.hadm_id,
        i.stay_id,
        i.intime,
        i.outtime,
        i.los,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON i.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON i.hadm_id = a.hadm_id
    WHERE p.anchor_age BETWEEN 84 AND 94
        AND p.gender = 'M'
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE di.hadm_id = i.hadm_id
                AND di.icd_code LIKE 'I63%'
                AND di.icd_version = 10
        )
),

first_stay AS (
    SELECT 
        subject_id,
        hadm_id,
        stay_id,
        intime,
        outtime,
        los,
        hospital_expire_flag,
        ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS stay_seq
    FROM stroke_cohort
),

map_data AS (
    SELECT 
        ce.stay_id,
        ce.valuenum AS map_value
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN first_stay fs
        ON ce.stay_id = fs.stay_id
    WHERE ce.itemid IN (220181, 225312)  -- MAP items
        AND ce.valuenum IS NOT NULL
        AND ce.charttime BETWEEN fs.intime AND DATETIME_ADD(fs.intime, INTERVAL 72 HOUR)
        AND fs.stay_seq = 1
),

instability_scores AS (
    SELECT 
        fs.subject_id,
        fs.hadm_id,
        fs.stay_id,
        fs.los,
        fs.hospital_expire_flag,
        STDDEV(md.map_value) AS instability_score
    FROM first_stay fs
    LEFT JOIN map_data md
        ON fs.stay_id = md.stay_id
    WHERE fs.stay_seq = 1
    GROUP BY 
        fs.subject_id,
        fs.hadm_id,
        fs.stay_id,
        fs.los,
        fs.hospital_expire_flag
    HAVING instability_score IS NOT NULL
),

cohort_stats AS (
    SELECT
        COUNT(*) AS total_patients,
        APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS q3_score
    FROM instability_scores
),

percentile_80 AS (
    SELECT
        COUNT(*) * 100.0 / MAX(total_patients) AS percentile
    FROM instability_scores
    CROSS JOIN cohort_stats
    WHERE instability_score <= 80
),

top_quartile AS (
    SELECT
        AVG(los) AS avg_icu_los,
        SUM(hospital_expire_flag) * 100.0 / COUNT(*) AS mortality_percent
    FROM instability_scores
    CROSS JOIN cohort_stats
    WHERE instability_score >= cohort_stats.q3_score
)

SELECT
    percentile_80.percentile AS percentile_of_80,
    top_quartile.avg_icu_los,
    top_quartile.mortality_percent
FROM percentile_80, top_quartile;