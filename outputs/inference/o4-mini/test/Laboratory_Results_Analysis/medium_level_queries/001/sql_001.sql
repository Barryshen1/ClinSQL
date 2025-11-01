WITH ami_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING (subject_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      USING (subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
      ON d.icd_code = di.icd_code
      AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND LOWER(di.long_title) LIKE '%acute myocardial infarction%'
),
troponin_items AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%troponin t%'
),
first_trop AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.subject_id, l.hadm_id ORDER BY l.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN troponin_items ti
      ON l.itemid = ti.itemid
    JOIN ami_patients ap
      ON l.subject_id = ap.subject_id
      AND l.hadm_id = ap.hadm_id
  WHERE
    l.valuenum IS NOT NULL
)
SELECT
  CASE
    WHEN valuenum <= 0.01 THEN 'normal'
    WHEN valuenum <= 0.03 THEN 'borderline'
    ELSE 'elevated'
  END AS category,
  COUNT(*) AS count
FROM
  first_trop
WHERE
  rn = 1
GROUP BY
  category
ORDER BY
  category;