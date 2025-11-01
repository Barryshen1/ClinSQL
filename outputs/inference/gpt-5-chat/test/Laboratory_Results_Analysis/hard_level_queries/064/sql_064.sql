WITH pancreatitis_cohort AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        p.gender,
        p.anchor_age,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 65 AND 75
      AND (
        (d.icd_version = 9 AND d.icd_code = '5770') OR
        (d.icd_version = 10 AND d.icd_code LIKE 'K85%')
      )
    GROUP BY p.subject_id, a.hadm_id, p.gender, p.anchor_age, a.admittime, a.dischtime, a.hospital_expire_flag
),
pancreatitis_labs AS (
    SELECT 
        coh.subject_id,
        coh.hadm_id,
        COUNTIF(l.valuenum IS NOT NULL AND (
            (l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower) OR
            (l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper)
        )) AS instability_score,
        COUNTIF(LOWER(l.flag) = 'critical') AS n_critical_labs
    FROM pancreatitis_cohort coh
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON coh.hadm_id = l.hadm_id
    WHERE l.charttime BETWEEN coh.admittime 
                          AND coh.admittime + INTERVAL 48 HOUR
    GROUP BY coh.subject_id, coh.hadm_id
),
pancreatitis_with_quintile AS (
    SELECT 
        pl.*,
        pc.admittime,
        pc.dischtime,
        pc.hospital_expire_flag,
        NTILE(5) OVER (ORDER BY pl.instability_score) AS quintile
    FROM pancreatitis_labs pl
    JOIN pancreatitis_cohort pc
      ON pl.hadm_id = pc.hadm_id
),
quintile_stats AS (
    SELECT 
        quintile,
        COUNT(*) AS n_admissions,
        AVG(instability_score) AS mean_instability,
        AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS mean_los_days,
        AVG(hospital_expire_flag) AS mortality_rate,
        100.0 * SUM(CASE WHEN n_critical_labs > 0 THEN 1 ELSE 0 END) / COUNT(*) AS pct_critical_labs
    FROM pancreatitis_with_quintile
    GROUP BY quintile
),
control_cohort AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        p.anchor_age,
        p.gender,
        a.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 65 AND 75
      AND a.hadm_id NOT IN (
          SELECT hadm_id FROM pancreatitis_cohort
      )
),
control_labs AS (
    SELECT 
        cc.hadm_id,
        COUNTIF(LOWER(l.flag) = 'critical') AS n_critical_labs
    FROM control_cohort cc
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON cc.hadm_id = l.hadm_id
    WHERE l.charttime BETWEEN cc.admittime 
                          AND cc.admittime + INTERVAL 48 HOUR
    GROUP BY cc.hadm_id
),
control_stats AS (
    SELECT 
        100.0 * SUM(CASE WHEN n_critical_labs > 0 THEN 1 ELSE 0 END) / COUNT(*) AS pct_critical_labs_control
    FROM control_labs
)
SELECT 
    q.quintile,
    q.n_admissions,
    q.mean_instability,
    q.mean_los_days,
    q.mortality_rate,
    q.pct_critical_labs,
    c.pct_critical_labs_control
FROM quintile_stats q
CROSS JOIN control_stats c
ORDER BY quintile;