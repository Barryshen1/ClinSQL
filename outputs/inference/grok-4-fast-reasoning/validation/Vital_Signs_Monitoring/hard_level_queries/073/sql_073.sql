WITH ich_hadms AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND (icd_code LIKE '430%' OR icd_code LIKE '431%' OR icd_code LIKE '432%'))
     OR (icd_version = 10 AND (icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%'))
),
female_age_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 47 AND 57
),
cohort_hadms AS (
  SELECT DISTINCT ih.subject_id, ih.hadm_id
  FROM ich_hadms ih
  INNER JOIN female_age_patients fap
    ON ih.subject_id = fap.subject_id AND ih.hadm_id = fap.hadm_id
),
cohort_with_icu AS (
  SELECT
    ch.hadm_id,
    ch.subject_id,
    a.hospital_expire_flag,
    SUM(ic.los) AS total_icu_los
  FROM cohort_hadms ch
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ch.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic
    ON ch.hadm_id = ic.hadm_id
  GROUP BY ch.hadm_id, ch.subject_id, a.hospital_expire_flag
),
first_stays AS (
  SELECT ic.hadm_id, ic.stay_id, ic.intime AS first_intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
  INNER JOIN cohort_hadms ch ON ic.hadm_id = ch.hadm_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ic.hadm_id ORDER BY ic.intime ASC) = 1
),
vitals AS (
  SELECT ce.stay_id, ce.charttime, ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN first_stays fs ON ce.stay_id = fs.stay_id
  WHERE ce.itemid IN (51, 552, 220179)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= fs.first_intime
    AND ce.charttime <= fs.first_intime + INTERVAL 72 HOUR
),
scores AS (
  SELECT
    fs.hadm_id,
    COALESCE(MAX(v.valuenum) - MIN(v.valuenum), 0) AS instability_score
  FROM first_stays fs
  LEFT JOIN vitals v ON fs.stay_id = v.stay_id
  GROUP BY fs.hadm_id
),
temp AS (
  SELECT
    s.hadm_id,
    s.instability_score,
    cw.total_icu_los,
    cw.hospital_expire_flag,
    PERCENTILE_CONT(0.9) OVER (ORDER BY s.instability_score ASC) AS threshold_90
  FROM scores s
  INNER JOIN cohort_with_icu cw ON s.hadm_id = cw.hadm_id
)
SELECT
  COUNTIF(instability_score <= 75) * 100.0 / COUNT(*) AS percentile_for_75,
  MAX(threshold_90) AS threshold_90,
  AVG(CASE WHEN instability_score >= threshold_90 THEN total_icu_los END) AS avg_los_top_decile,
  AVG(CASE WHEN instability_score >= threshold_90 THEN hospital_expire_flag * 1.0 END) AS mortality_top_decile
FROM temp;