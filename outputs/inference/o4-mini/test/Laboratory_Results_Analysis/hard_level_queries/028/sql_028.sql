WITH
-- 1. Base female, age 74-84 admissions
base_adm AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING (subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 74 AND 84
),

-- 2. Identify ICH admissions
ich_adm AS (
  SELECT DISTINCT ba.hadm_id
  FROM
    base_adm ba
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      USING (subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dc
      USING (icd_code, icd_version)
  WHERE
    LOWER(dc.long_title) LIKE '%intracranial hemorrhage%'
),

-- 3. Compute lab-based metrics in first 72h
lab_metrics AS (
  SELECT
    ba.hadm_id,
    -- Instability count: distinct itemid outside reference range
    COUNT(DISTINCT CASE
      WHEN le.valuenum IS NOT NULL
        AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
      THEN le.itemid
    END) AS instability_count,
    -- Critical lab count
    COUNTIF(le.flag = 'crit') AS critical_count
  FROM
    base_adm ba
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON ba.hadm_id = le.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
      ON le.itemid = li.itemid
  WHERE
    le.charttime BETWEEN ba.admittime AND TIMESTAMP_ADD(ba.admittime, INTERVAL 72 HOUR)
  GROUP BY
    ba.hadm_id
),

-- 4. Annotate cohorts with metrics
cohort_metrics AS (
  SELECT
    ba.hadm_id,
    ba.hospital_expire_flag,
    ba.los_days,
    COALESCE(lm.instability_count, 0)      AS instability_count,
    COALESCE(lm.critical_count, 0)         AS critical_count,
    CASE
      WHEN ia.hadm_id IS NOT NULL THEN 'ICH'
      ELSE 'Control'
    END AS cohort
  FROM
    base_adm ba
    LEFT JOIN ich_adm ia USING (hadm_id)
    LEFT JOIN lab_metrics lm USING (hadm_id)
),

-- 5. Compute quintiles within the ICH cohort and extract cutpoints
ich_quintiles AS (
  SELECT
    hadm_id,
    hospital_expire_flag,
    los_days,
    instability_count,
    critical_count,
    NTILE(5) OVER (ORDER BY instability_count) AS quintile
  FROM
    cohort_metrics
  WHERE cohort = 'ICH'
),
quintile_cutoffs AS (
  SELECT
    quintile,
    MIN(instability_count) AS min_ic,
    MAX(instability_count) AS max_ic
  FROM ich_quintiles
  GROUP BY quintile
),

-- 6. Summarize ICH by quintile
ich_summary AS (
  SELECT
    quintile,
    COUNT(*)                        AS n_ich,
    AVG(hospital_expire_flag)       AS mortality_rate_ich,
    AVG(los_days)                   AS mean_los_ich,
    AVG(critical_count)             AS mean_critlabs_ich
  FROM ich_quintiles
  GROUP BY quintile
),

-- 7. Assign controls to quintile based on the same cutpoints
control_with_quintile AS (
  SELECT
    cm.*,
    qc.quintile
  FROM
    cohort_metrics cm
    JOIN quintile_cutoffs qc
      ON cm.instability_count BETWEEN qc.min_ic AND qc.max_ic
  WHERE
    cm.cohort = 'Control'
),

-- 8. Summarize controls by quintile
control_summary AS (
  SELECT
    quintile,
    COUNT(*)                        AS n_ctrl,
    AVG(hospital_expire_flag)       AS mortality_rate_ctrl,
    AVG(los_days)                   AS mean_los_ctrl,
    AVG(critical_count)             AS mean_critlabs_ctrl
  FROM control_with_quintile
  GROUP BY quintile
)

-- 9. Final side-by-side comparison
SELECT
  ich.quintile,
  ich.n_ich,
  ich.mortality_rate_ich,
  ich.mean_los_ich,
  ich.mean_critlabs_ich,
  ctrl.n_ctrl,
  ctrl.mortality_rate_ctrl,
  ctrl.mean_los_ctrl,
  ctrl.mean_critlabs_ctrl
FROM
  ich_summary ich
  JOIN control_summary ctrl
    USING (quintile)
ORDER BY
  quintile;