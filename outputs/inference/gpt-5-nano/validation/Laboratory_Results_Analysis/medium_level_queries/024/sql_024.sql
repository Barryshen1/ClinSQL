WITH chest_pain_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 64 AND 74
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS did
        ON di.icd_code = did.icd_code
       AND di.icd_version = did.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND LOWER(did.long_title) LIKE '%chest pain%'
    )
),
troponin_events AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS di
    ON le.itemid = di.itemid
  WHERE le.subject_id IN (SELECT subject_id FROM chest_pain_admissions)
    AND le.hadm_id IN (SELECT hadm_id FROM chest_pain_admissions)
    AND le.charttime IS NOT NULL
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 14
    AND (LOWER(di.label) LIKE '%hs%troponin%'
         OR LOWER(di.label) LIKE '%troponin t%')
    AND (LOWER(le.valueuom) LIKE '%ng%l%')
),
first_high_troponin AS (
  SELECT
    subject_id,
    hadm_id,
    MIN(charttime) AS first_high_troponin_time
  FROM troponin_events
  GROUP BY subject_id, hadm_id
)
SELECT
  COUNT(DISTINCT cpa.hadm_id) AS n_admissions,
  AVG(p.anchor_age) AS avg_age,
  APPROX_QUANTILES(p.anchor_age, 100)[OFFSET(50)] AS median_age,
  AVG(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS avg_los_days,
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_deaths,
  AVG(CASE WHEN a.hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) AS in_hospital_mortality_rate
FROM chest_pain_admissions AS cpa
JOIN first_high_troponin AS fht
  ON fht.hadm_id = cpa.hadm_id
 AND fht.subject_id = cpa.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  ON a.hadm_id = cpa.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON p.subject_id = a.subject_id;