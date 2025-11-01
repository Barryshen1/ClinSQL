WITH ap_cohort AS (
  SELECT 
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND (pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 63 AND 73
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 10 AND diag.icd_code LIKE 'K85%')
          OR (diag.icd_version = 9 AND diag.icd_code = '5770')
        )
    )
),
lab_instability AS (
  SELECT 
    ac.hadm_id,
    COUNT(*) AS critical_lab_count
  FROM ap_cohort ac
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ac.hadm_id = le.hadm_id
    AND le.charttime BETWEEN ac.admittime AND ac.admittime + INTERVAL '72' HOUR
    AND le.flag = 'critical'
  GROUP BY ac.hadm_id
),
p90_value AS (
  SELECT 
    APPROX_QUANTILES(critical_lab_count, 100)[SAFE_OFFSET(90)] AS p90
  FROM lab_instability
),
high_group AS (
  SELECT 
    ac.hadm_id,
    ac.admittime,
    ac.dischtime,
    ac.hospital_expire_flag
  FROM ap_cohort ac
  INNER JOIN lab_instability li
    ON ac.hadm_id = li.hadm_id
  CROSS JOIN p90_value p
  WHERE li.critical_lab_count >= p.p90
),
high_group_stats AS (
  SELECT 
    AVG(hospital_expire_flag) AS mortality,
    AVG(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_days
  FROM high_group
),
high_group_labs AS (
  SELECT 
    hg.hadm_id,
    le.itemid
  FROM high_group hg
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON hg.hadm_id = le.hadm_id
    AND le.charttime BETWEEN hg.admittime AND hg.admittime + INTERVAL '72' HOUR
    AND le.flag = 'critical'
),
high_group_rates AS (
  SELECT 
    itemid,
    COUNT(DISTINCT hadm_id) * 1.0 / GREATEST((SELECT COUNT(*) FROM high_group), 1) AS critical_rate_high
  FROM high_group_labs
  GROUP BY itemid
),
general_labs AS (
  SELECT 
    adm.hadm_id,
    le.itemid
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON adm.hadm_id = le.hadm_id
    AND le.charttime BETWEEN adm.admittime AND adm.admittime + INTERVAL '72' HOUR
    AND le.flag = 'critical'
),
general_rates AS (
  SELECT 
    itemid,
    COUNT(DISTINCT hadm_id) * 1.0 / GREATEST((SELECT COUNT(*) FROM `physionet-data.mimiciv_3_1_hosp.admissions`), 1) AS critical_rate_general
  FROM general_labs
  GROUP BY itemid
)
SELECT 
  dli.label AS lab_label,
  hgr.critical_rate_high,
  COALESCE(gr.critical_rate_general, 0) AS critical_rate_general,
  hgs.mortality,
  hgs.mean_los_days
FROM high_group_rates hgr
LEFT JOIN general_rates gr
  ON hgr.itemid = gr.itemid
CROSS JOIN high_group_stats hgs
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
  ON hgr.itemid = dli.itemid
ORDER BY lab_label;