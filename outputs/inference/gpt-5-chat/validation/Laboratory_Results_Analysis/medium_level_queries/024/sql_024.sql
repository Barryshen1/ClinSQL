WITH chest_pain_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
    AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND di.seq_num = 1 -- primary dx
    AND LOWER(dd.long_title) LIKE '%chest pain%'
),
troponin_first AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    MIN(l.charttime) AS first_charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON l.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%high sensitivity troponin t%'
    AND l.valuenum IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
  GROUP BY l.subject_id, l.hadm_id
),
troponin_values AS (
  SELECT
    cpa.subject_id,
    cpa.hadm_id,
    cpa.gender,
    cpa.anchor_age,
    cpa.hospital_expire_flag,
    l.valuenum,
    l.ref_range_upper
  FROM chest_pain_admissions cpa
  JOIN troponin_first tf
    ON cpa.subject_id = tf.subject_id
    AND cpa.hadm_id = tf.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON tf.subject_id = l.subject_id
    AND tf.hadm_id = l.hadm_id
    AND tf.first_charttime = l.charttime
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON l.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%high sensitivity troponin t%'
    AND l.valuenum IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
    AND l.valuenum > l.ref_range_upper
)
SELECT
  COUNT(*) AS num_patients,
  ROUND(AVG(valuenum),2) AS avg_first_troponin,
  ROUND(STDDEV_POP(valuenum),2) AS sd_first_troponin,
  ROUND(MIN(valuenum),2) AS min_first_troponin,
  ROUND(MAX(valuenum),2) AS max_first_troponin,
  ROUND(100 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*),2) AS in_hospital_mortality_rate_pct
FROM troponin_values;