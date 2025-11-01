WITH cohort AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.discharge_location,
        adm.hospital_expire_flag,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        CASE 
            WHEN adm.hospital_expire_flag = 1 THEN 'DEATH'
            WHEN adm.discharge_location = 'HOME' THEN 'HOME'
            ELSE 'FACILITY' 
        END AS disposition
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE 
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 52 AND 62
        AND adm.admission_type = 'TRANSFER'
        AND adm.dischtime IS NOT NULL
),
stats AS (
    SELECT 
        disposition,
        COUNT(*) AS n_cases,
        ROUND(AVG(los_days), 2) AS mean_los,
        ROUND(STDDEV(los_days), 2) AS sd_los
    FROM cohort
    GROUP BY disposition
),
percentiles AS (
    SELECT 
        disposition,
        los_days,
        PERCENT_RANK() OVER (PARTITION BY disposition ORDER BY los_days) * 100 AS pct_rank
    FROM cohort
)
SELECT 
    s.disposition,
    s.n_cases,
    CONCAT(s.mean_los, ' ± ', s.sd_los) AS mean_sd_los,
    MAX(CASE WHEN p.los_days = 5 THEN p.pct_rank END) AS percentile_rank_5_day_los
FROM stats s
LEFT JOIN percentiles p
    ON s.disposition = p.disposition
GROUP BY s.disposition, s.n_cases, s.mean_los, s.sd_los
ORDER BY s.disposition;