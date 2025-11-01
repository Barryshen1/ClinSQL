WITH patients_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 77 AND 87
),
ami_admissions AS (
  SELECT
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    dd.icd_version = 10
    AND dd.long_title LIKE '%myocardial infarction%'
),
first_hstnt AS (
  SELECT
    le.hadm_id,
    le.valuenum,
    le.valueuom
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  WHERE
    le.itemid = 399250
  QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC) = 1
)
SELECT
  CASE
    WHEN fh.valuenum < 14 THEN 'normal'
    WHEN fh.valuenum BETWEEN 14 AND 34 THEN 'borderline'
    WHEN fh.valuenum > 34 THEN 'myocardial injury'
    ELSE 'unknown'
  END AS troponin_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM
  patients_admissions pa
JOIN
  ami_admissions aa
  ON pa.hadm_id = aa.hadm_id
JOIN
  first_hstnt fh
  ON pa.hadm_id = fh.hadm_id
GROUP BY
  troponin_category
ORDER BY
  troponin_category;