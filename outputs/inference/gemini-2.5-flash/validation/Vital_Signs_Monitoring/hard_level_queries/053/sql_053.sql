WITH cohort_patients AS (
    SELECT
        pa.subject_id,
        ad.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.outtime,
        icu.los,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON pa.subject_id = ad.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON ad.hadm_id = icu.hadm_id
    WHERE
        pa.gender = 'F'
        AND pa.anchor_age BETWEEN 59 AND 69
),
shock_status AS (
    SELECT
        c.subject_id,
        c.hadm_id,
        c.stay_id,
        -- Check for ICD-10 codes related to shock (e.g., R57.x)
        MAX(CASE WHEN LOWER(di.icd_code) LIKE 'r57%' AND di.icd_version = 10 THEN 1 ELSE 0 END) AS has_shock
    FROM
        cohort_patients c
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON c.subject_id = di.subject_id AND c.hadm_id = di.hadm_id
    GROUP BY
        c.subject_id, c.hadm_id, c.stay_id
),
vitals_first_24hr AS (
    SELECT
        c.subject_id,
        c.hadm_id,
        c.stay_id,
        ce.charttime,
        -- Mean Arterial Pressure (MAP)
        MAX(CASE WHEN ce.itemid IN (220052, 220181) THEN ce.valuenum END) AS MAP_val,
        -- Heart Rate
        MAX(CASE WHEN ce.itemid = 220045 THEN ce.valuenum END) AS HR_val,
        -- Respiratory Rate
        MAX(CASE WHEN ce.itemid = 220210 THEN ce.valuenum END) AS RR_val
    FROM
        cohort_patients c
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON c.subject_id = ce.subject_id AND c.stay_id = ce.stay_id
    WHERE
        ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
        AND ce.valuenum IS NOT NULL
        AND ce.itemid IN (220052, 220181, 220045, 220210)
    GROUP BY
        c.subject_id, c.hadm_id, c.stay_id, ce.charttime
),
cis_components AS (
    SELECT
        v.subject_id,
        v.hadm_id,
        v.stay_id,
        v.charttime,
        v.MAP_val,
        v.HR_val,
        v.RR_val,
        -- Calculate individual deviation scores for CIS components
        -- HR deviation (normal 60-100 bpm)
        COALESCE(
            CASE
                WHEN v.HR_val < 60 THEN 60 - v.HR_val
                WHEN v.HR_val > 100 THEN v.HR_val - 100
                ELSE 0
            END, 0
        ) AS hr_deviation_score,
        -- MAP deviation (normal 65-100 mmHg)
        COALESCE(
            CASE
                WHEN v.MAP_val < 65 THEN 65 - v.MAP_val
                WHEN v.MAP_val > 100 THEN v.MAP_val - 100
                ELSE 0
            END, 0
        ) AS map_deviation_score,
        -- RR deviation (normal 12-20 bpm)
        COALESCE(
             CASE
                WHEN v.RR_val < 12 THEN 12 - v.RR_val
                WHEN v.RR_val > 20 THEN v.RR_val - 20
                ELSE 0
            END, 0
        ) AS rr_deviation_score
    FROM
        vitals_first_24hr v
),
patient_vitals_summary AS (
    SELECT
        c.subject_id,
        c.hadm_id,
        c.stay_id,
        -- Composite Instability Score (CIS): average of sum of deviation scores across timepoints in first 24 hours
        AVG(cc.hr_deviation_score + cc.map_deviation_score + cc.rr_deviation_score) AS avg_cis,
        -- Hypotension burden (MAP < 65): percentage of valid MAP measurements that are < 65
        SUM(CASE WHEN cc.MAP_val < 65 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(cc.MAP_val), 0) AS hypotension_burden,
        -- Tachycardia burden (HR > 100): percentage of valid HR measurements that are > 100
        SUM(CASE WHEN cc.HR_val > 100 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(cc.HR_val), 0) AS tachycardia_burden
    FROM
        cohort_patients c
    LEFT JOIN
        cis_components cc
        ON c.subject_id = cc.subject_id AND c.hadm_id = cc.hadm_id AND c.stay_id = cc.stay_id
    GROUP BY
        c.subject_id, c.hadm_id, c.stay_id
)
SELECT
    ss.has_shock,
    COUNT(DISTINCT c.stay_id) AS num_icu_stays,

    -- Composite Instability Score (CIS)
    AVG(pvs.avg_cis) AS mean_cis,
    APPROX_QUANTILES(pvs.avg_cis, 100)[OFFSET(25)] AS p25_cis,
    APPROX_QUANTILES(pvs.avg_cis, 100)[OFFSET(50)] AS p50_cis,
    APPROX_QUANTILES(pvs.avg_cis, 100)[OFFSET(75)] AS p75_cis,
    APPROX_QUANTILES(pvs.avg_cis, 100)[OFFSET(90)] AS p90_cis,

    -- Hypotension burden
    AVG(pvs.hypotension_burden) AS mean_hypotension_burden,
    APPROX_QUANTILES(pvs.hypotension_burden, 100)[OFFSET(25)] AS p25_hypotension_burden,
    APPROX_QUANTILES(pvs.hypotension_burden, 100)[OFFSET(50)] AS p50_hypotension_burden,
    APPROX_QUANTILES(pvs.hypotension_burden, 100)[OFFSET(75)] AS p75_hypotension_burden,
    APPROX_QUANTILES(pvs.hypotension_burden, 100)[OFFSET(90)] AS p90_hypotension_burden,

    -- Tachycardia burden
    AVG(pvs.tachycardia_burden) AS mean_tachycardia_burden,
    APPROX_QUANTILES(pvs.tachycardia_burden, 100)[OFFSET(25)] AS p25_tachycardia_burden,
    APPROX_QUANTILES(pvs.tachycardia_burden, 100)[OFFSET(50)] AS p50_tachycardia_burden,
    APPROX_QUANTILES(pvs.tachycardia_burden, 100)[OFFSET(75)] AS p75_tachycardia_burden,
    APPROX_QUANTILES(pvs.tachycardia_burden, 100)[OFFSET(90)] AS p90_tachycardia_burden,

    -- ICU Length of Stay (LOS)
    AVG(c.los) AS mean_icu_los,
    APPROX_QUANTILES(c.los, 100)[OFFSET(25)] AS p25_icu_los,
    APPROX_QUANTILES(c.los, 100)[OFFSET(50)] AS p50_icu_los,
    APPROX_QUANTILES(c.los, 100)[OFFSET(75)] AS p75_icu_los,
    APPROX_QUANTILES(c.los, 100)[OFFSET(90)] AS p90_icu_los,

    -- Hospital Mortality
    AVG(c.hospital_expire_flag) AS mortality_rate
FROM
    cohort_patients c
INNER JOIN
    shock_status ss
    ON c.subject_id = ss.subject_id AND c.hadm_id = ss.hadm_id AND c.stay_id = ss.stay_id
LEFT JOIN
    patient_vitals_summary pvs
    ON c.subject_id = pvs.subject_id AND c.hadm_id = pvs.hadm_id AND c.stay_id = pvs.stay_id
GROUP BY
    ss.has_shock
ORDER BY
    ss.has_shock;