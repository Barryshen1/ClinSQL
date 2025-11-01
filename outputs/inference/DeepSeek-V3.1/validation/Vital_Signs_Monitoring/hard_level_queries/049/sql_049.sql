WITH cohort AS (
    SELECT
        ie.subject_id, 
        ie.hadm_id, 
        ie.stay_id,
        ie.los AS icu_los,
        adm.hospital_expire_flag,
        MAX(CASE WHEN ce.itemid = 220045 THEN ce.valuenum ELSE NULL END) AS instability_score
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON ie.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON ie.hadm_id = adm.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON ie.stay_id = ce.stay_id
        AND ce.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
        AND ce.itemid = 220045  -- Heart rate
    WHERE 
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 78 AND 88
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
            WHERE ie.hadm_id = diag.hadm_id
            AND (
                (diag.icd_version = 9 AND diag.icd_code LIKE '995.9%') OR
                (diag.icd_version = 10 AND diag.icd_code LIKE 'R65.2%')
            )
        )
    GROUP BY ie.subject_id, ie.hadm_id, ie.stay_id, ie.los, adm.hospital_expire_flag
    HAVING instability_score IS NOT NULL
),

percentile_info AS (
    SELECT
        PERCENT_RANK() OVER (ORDER BY instability_score) AS percentile
    FROM cohort
    WHERE instability_score = 85
    LIMIT 1
),

quartiles AS (
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        icu_los,
        hospital_expire_flag,
        instability_score,
        NTILE(4) OVER (ORDER BY instability_score) AS quartile
    FROM cohort
),

q4_stats AS (
    SELECT
        AVG(icu_los) AS mean_icu_los,
        AVG(hospital_expire_flag) AS hospital_mortality
    FROM quartiles
    WHERE quartile = 4
)

SELECT 
    (SELECT percentile FROM percentile_info) AS percentile_rank_of_85,
    (SELECT mean_icu_los FROM q4_stats) AS mean_icu_los_q4,
    (SELECT hospital_mortality FROM q4_stats) AS hospital_mortality_q4;