WITH age_at_admit AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.insurance,
    (p.anchor_age - (p.anchor_year - EXTRACT(YEAR FROM a.admittime))) AS age_at_admit
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
index_admissions AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM
    age_at_admit
),
filtered_index AS (
  SELECT
    ia.*
  FROM
    index_admissions ia
  WHERE
    rn = 1
    AND ia.gender = 'F'
    AND ia.age_at_admit BETWEEN 68 AND 78
    AND ia.insurance = 'Medicare'
    AND LOWER(ia.admission_location) LIKE '%emergency%'
),
stroke_diagnoses AS (
  SELECT
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses dc
  ON
    d.icd_code = dc.icd_code AND d.icd_version = dc.icd_version
  WHERE
    d.seq_num = 1  -- Principal diagnosis
    AND (
      (d.icd_version = 9 AND d.icd_code BETWEEN '430' AND '432')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%')
    )
)
SELECT
  COUNT(*) AS cohort_count
FROM
  filtered_index fi
INNER JOIN
  stroke_diagnoses sd
ON
  fi.hadm_id = sd.hadm_id;