WITH cohort AS (
    SELECT 
        p.subject_id, 
        p.gender, 
        p.anchor_age,
        ie.hadm_id,
        ie.stay_id,
        ie.intime,
        ie.outtime,
        ie.los AS icu_los,
        adm.hospital_expire_flag AS mortality
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON ie.hadm_id = adm.hadm_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 40 AND 50
        AND EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
            WHERE ie.hadm_id = diag.hadm_id
            AND (
                (diag.icd_code LIKE 'J96%' AND diag.icd_version = 10)
                OR (diag.icd_code = '518.81' AND diag.icd_version = 9)
            )
        )
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ie.hadm_id ORDER BY ie.intime) = 1
),

map_hr_events AS (
    SELECT 
        c.stay_id,
        ce.charttime,
        CASE WHEN ce.itemid IN (456, 52, 6702, 443, 220052, 220181) THEN 'MAP' 
             WHEN ce.itemid IN (211, 220045) THEN 'HR' 
        END AS vital_type,
        ce.valuenum
    FROM cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON c.stay_id = ce.stay_id
    WHERE ce.itemid IN (456, 52, 6702, 443, 220052, 220181, 211, 220045)
        AND ce.valuenum IS NOT NULL
        AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
),

hourly_medians AS (
    SELECT 
        stay_id,
        DATETIME_TRUNC(charttime, HOUR) AS chart_hour,
        vital_type,
        APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median_value
    FROM map_hr_events
    GROUP BY stay_id, chart_hour, vital_type
),

pivot_hourly AS (
    SELECT 
        stay_id,
        chart_hour,
        MAX(CASE WHEN vital_type = 'MAP' THEN median_value END) AS median_map,
        MAX(CASE WHEN vital_type = 'HR' THEN median_value END) AS median_hr
    FROM hourly_medians
    GROUP BY stay_id, chart_hour
),

vii_per_hour AS (
    SELECT 
        stay_id,
        chart_hour,
        median_map,
        median_hr,
        (ABS(median_map - 90) + ABS(median_hr - 75)) / 2 AS vii
    FROM pivot_hourly
    WHERE median_map IS NOT NULL AND median_hr IS NOT NULL
),

patient_summary AS (
    SELECT 
        stay_id,
        AVG(vii) AS mean_vii,
        COUNT(*) AS num_hours,
        SUM(CASE WHEN median_map < 65 THEN 1 ELSE 0 END) / COUNT(median_map) AS hypotensive_burden,
        SUM(CASE WHEN median_hr > 100 THEN 1 ELSE 0 END) / COUNT(median_hr) AS tachycardic_burden
    FROM vii_per_hour
    GROUP BY stay_id
)

SELECT 
    'Overall' AS subgroup,
    COUNT(*) AS n_patients,
    STDDEV(ps.mean_vii) AS vii_sd,
    APPROX_QUANTILES(ps.mean_vii, 100)[OFFSET(25)] AS vii_p25,
    APPROX_QUANTILES(ps.mean_vii, 100)[OFFSET(50)] AS vii_p50,
    APPROX_QUANTILES(ps.mean_vii, 100)[OFFSET(75)] AS vii_p75,
    APPROX_QUANTILES(ps.mean_vii, 100)[OFFSET(95)] AS vii_p95,
    AVG(ps.hypotensive_burden) AS avg_hypotensive_burden,
    AVG(ps.tachycardic_burden) AS avg_tachycardic_burden,
    AVG(c.icu_los) AS avg_icu_los,
    AVG(c.mortality) AS mortality_rate
FROM cohort c
INNER JOIN patient_summary ps
    ON c.stay_id = ps.stay_id
GROUP BY subgroup;