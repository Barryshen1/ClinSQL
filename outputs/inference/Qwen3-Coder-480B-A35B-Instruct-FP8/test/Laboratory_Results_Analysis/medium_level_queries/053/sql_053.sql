WITH troponin_first AS (
  SELECT
    l.hadm_id,
    l.valuenum AS first_troponin,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents AS l
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems AS d
    ON l.itemid = d.itemid
  WHERE
    LOWER(d.label) LIKE '%troponin i%'
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0.04
)
SELECT
  COUNT(DISTINCT p.subject_id) AS patient_count,
  COUNT(DISTINCT a.hadm_id) AS admission_count,
  AVG(t.first_troponin) AS mean_troponin,
  STDDEV(t.first_troponin) AS stddev_troponin,
  MIN(t.first_troponin) AS min_troponin,
  MAX(t.first_troponin) AS max_troponin
FROM
  physionet-data.mimiciv_3_1_hosp.patients AS p
INNER JOIN
  physionet-data.mimiciv_3_1_hosp.admissions AS a
  ON p.subject_id = a.subject_id
INNER JOIN
  physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS d_icd
  ON a.hadm_id = d_icd.hadm_id
INNER JOIN
  physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses AS d_diag
  ON d_icd.icd_code = d_diag.icd_code
  AND d_icd.icd_version = d_diag.icd_version
INNER JOIN
  troponin_first AS t
  ON a.hadm_id = t.hadm_id
  AND t.rn = 1
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 68 AND 78
  AND LOWER(d_diag.long_title) LIKE '%acute coronary%';