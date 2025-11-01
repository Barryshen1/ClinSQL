WITH chest_pain_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.hospital_expire_flag,
         p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admit
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%chest pain%'
    AND p.gender = 'M'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 64 AND 74
),

troponin_first AS (
  SELECT l.hadm_id, MIN(l.charttime) AS first_charttime
  FROM physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN physionet-data.mimiciv_3_1_hosp.d_labitems d
    ON l.itemid = d.itemid
  WHERE LOWER(d.label) LIKE '%troponin t%'
    AND LOWER(d.label) LIKE '%high sensitivity%'
    AND l.valuenum IS NOT NULL
  GROUP BY l.hadm_id
),

troponin_values AS (
  SELECT l.hadm_id, l.valuenum AS troponin_value
  FROM physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN troponin_first tf
    ON l.hadm_id = tf.hadm_id AND l.charttime = tf.first_charttime
  JOIN physionet-data.mimiciv_3_1_hosp.d_labitems d
    ON l.itemid = d.itemid
  WHERE LOWER(d.label) LIKE '%troponin t%'
    AND LOWER(d.label) LIKE '%high sensitivity%'
    AND l.valuenum > 0.014
)

SELECT 
  COUNT(*) AS patient_count,
  AVG(age_at_admit) AS mean_age,
  STDDEV(age_at_admit) AS stddev_age,
  AVG(troponin_value) AS mean_trop_t,
  STDDEV(troponin_value) AS stddev_trop_t,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality
FROM chest_pain_admissions cpa
JOIN troponin_values tv
  ON cpa.hadm_id = tv.hadm_id;