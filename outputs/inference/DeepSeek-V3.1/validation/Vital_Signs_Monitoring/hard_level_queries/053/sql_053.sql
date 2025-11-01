WITH cohort AS (
    SELECT 
        ie.stay_id,
        ie.subject_id,
        ie.hadm_id,
        ie.intime,
        ie.outtime,
        ie.los AS icu_los,
        CASE 
            WHEN adm.hospital_expire_flag = 1 THEN 1
            ELSE 0 
        END AS hospital_expire_flag,
        CASE 
            WHEN diag.icd_code IS NOT NULL THEN 1
            ELSE 0 
        END AS shock
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON ie.hadm_id = adm.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON ie.hadm_id = diag.hadm_id
        AND diag.icd_code IN ('78550', '78551', '78552', '78559', 'R571', 'R579')  -- Shock ICD-9 and ICD-10 codes
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 59 AND 69
),

vitals AS (
    SELECT 
        c.stay_id,
        -- Hypotension: MAP < 65
        AVG(CASE WHEN ce.itemid = 220181 AND ce.valuenum < 65 THEN 1.0 ELSE 0.0 END) AS hypotension_burden,
        -- Tachycardia: HR > 100
        AVG(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 100 THEN 1.0 ELSE 0.0 END) AS tachycardia_burden
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON c.stay_id = ce.stay_id
        AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
        AND ce.itemid IN (220181, 220045)
    GROUP BY c.stay_id
)

SELECT 
    c.shock,
    COUNT(*) AS n_stays,
    AVG(COALESCE(v.hypotension_burden, 0)) AS mean_hypotension_burden,
    APPROX_QUANTILES(COALESCE(v.hypotension_burden, 0), 100)[OFFSET(25)] AS p25_hypotension_burden,
    APPROX_QUANTILES(COALESCE(v.hypotension_burden, 0), 100)[OFFSET(50)] AS p50_hypotension_burden,
    APPROX_QUANTILES(COALESCE(v.hypotension_burden, 0), 100)[OFFSET(75)] AS p75_hypotension_burden,
    AVG(COALESCE(v.tachycardia_burden, 0)) AS mean_tachycardia_burden,
    APPROX_QUANTILES(COALESCE(v.tachycardia_burden, 0), 100)[OFFSET(25)] AS p25_tachycardia_burden,
    APPROX_QUANTILES(COALESCE(v.tachycardia_burden, 0), 100)[OFFSET(50)] AS p50_tachycardia_burden,
    APPROX_QUANTILES(COALESCE(v.tachycardia_burden, 0), 100)[OFFSET(75)] AS p75_tachycardia_burden,
    AVG(c.icu_los) AS mean_icu_los,
    APPROX_QUANTILES(c.icu_los, 100)[OFFSET(25)] AS p25_icu_los,
    APPROX_QUANTILES(c.icu_los, 100)[OFFSET(50)] AS p50_icu_los,
    APPROX_QUANTILES(c.icu_los, 100)[OFFSET(75)] AS p75_icu_los,
    AVG(c.hospital_expire_flag) AS mortality_rate
FROM cohort c
LEFT JOIN vitals v
    ON c.stay_id = v.stay_id
GROUP BY c.shock
ORDER BY c.shock;