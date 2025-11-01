WITH cohort AS (
    SELECT 
        p.subject_id, 
        p.anchor_age,
        a.hadm_id, 
        a.admittime, 
        a.dischtime, 
        a.hospital_expire_flag,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON a.hadm_id = di.hadm_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 73 AND 83
        AND (
            (di.icd_version = 10 AND di.icd_code LIKE 'I61%') 
            OR (di.icd_version = 9 AND di.icd_code = '431')
        )
),

labs_48hr AS (
    SELECT 
        c.subject_id, 
        c.hadm_id,
        COUNT(DISTINCT l.itemid) AS instability_score
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
        ON c.hadm_id = l.hadm_id
        AND l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
        AND l.flag = 'abnormal'
    GROUP BY c.subject_id, c.hadm_id
),

cohort_with_score AS (
    SELECT 
        c.*, 
        COALESCE(l.instability_score, 0) AS instability_score,
        NTILE(4) OVER (ORDER BY COALESCE(l.instability_score, 0)) AS quartile
    FROM cohort c
    LEFT JOIN labs_48hr l
        ON c.hadm_id = l.hadm_id
),

quartile_summary AS (
    SELECT 
        quartile,
        COUNT(*) AS count_patients,
        AVG(los_days) AS mean_los,
        AVG(hospital_expire_flag) AS mortality_rate
    FROM cohort_with_score
    GROUP BY quartile
),

overall_mortality AS (
    SELECT AVG(hospital_expire_flag) AS overall_mortality_rate
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
)

SELECT 
    q.quartile,
    q.count_patients,
    q.mean_los,
    q.mortality_rate,
    o.overall_mortality_rate,
    q.mortality_rate - o.overall_mortality_rate AS mortality_rate_diff
FROM quartile_summary q
CROSS JOIN overall_mortality o
ORDER BY q.quartile;