WITH patients_female AS (
  SELECT subject_id, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 41 AND 51
),
stays AS (
  SELECT s.subject_id, s.hadm_id, s.stay_id, s.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  INNER JOIN patients_female p ON s.subject_id = p.subject_id
),
rr_items AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%respiratory rate%' OR LOWER(label) LIKE '%resp rate%' OR LOWER(label) LIKE '%rr%'
),
rr_data AS (
  SELECT ce.subject_id, ce.hadm_id, ce.stay_id, ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN stays s ON ce.subject_id = s.subject_id AND ce.stay_id = s.stay_id
  INNER JOIN rr_items ri ON ce.itemid = ri.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime >= s.intime
    AND ce.charttime <= TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
    AND ce.valuenum > 0
    AND ce.valuenum < 100
),
avg_rr AS (
  SELECT subject_id, hadm_id, stay_id, AVG(valuenum) AS avg_rr
  FROM rr_data
  GROUP BY subject_id, hadm_id, stay_id
  HAVING COUNT(valuenum) >= 1
),
binned_rr AS (
  SELECT ar.subject_id, ar.hadm_id, ar.stay_id, ar.avg_rr,
    CASE
      WHEN ar.avg_rr < 12 THEN '<12'
      WHEN ar.avg_rr >= 12 AND ar.avg_rr <= 20 THEN '12-20'
      WHEN ar.avg_rr >= 21 AND ar.avg_rr <= 29 THEN '21-29'
      WHEN ar.avg_rr >= 30 THEN '>=30'
    END AS rr_bin
  FROM avg_rr ar
  WHERE ar.avg_rr IS NOT NULL
),
stroke_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%stroke%'
     OR LOWER(long_title) LIKE '%infarction%'
     OR LOWER(long_title) LIKE '%hemorrhage%'
     OR LOWER(long_title) LIKE '%cerebrovascular%'
),
strokes AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN stroke_codes sc ON di.icd_code = sc.icd_code AND di.icd_version = sc.icd_version
  INNER JOIN stays s ON di.subject_id = s.subject_id AND di.hadm_id = s.hadm_id
)
SELECT
  rr_bin,
  COUNT(*) AS num_stays,
  COUNT(DISTINCT br.hadm_id) AS total_admissions,
  COUNT(DISTINCT CASE WHEN st.subject_id IS NOT NULL THEN br.hadm_id END) AS num_stroke_admissions,
  ROUND(
    COUNT(DISTINCT CASE WHEN st.subject_id IS NOT NULL THEN br.hadm_id END) * 100.0 /
    COUNT(DISTINCT br.hadm_id), 2
  ) AS stroke_rate_percent
FROM binned_rr br
LEFT JOIN strokes st ON br.subject_id = st.subject_id AND br.hadm_id = st.hadm_id
GROUP BY rr_bin
ORDER BY
  CASE rr_bin
    WHEN '<12' THEN 1
    WHEN '12-20' THEN 2
    WHEN '21-29' THEN 3
    WHEN '>=30' THEN 4
  END;