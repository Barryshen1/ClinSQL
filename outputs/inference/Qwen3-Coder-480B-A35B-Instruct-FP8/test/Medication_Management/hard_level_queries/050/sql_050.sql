WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.los,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
),

aki_patients AS (
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id,
    c.los,
    c.hospital_expire_flag
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON
    c.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%acute kidney injury%'
),

meds AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT drug) AS med_complexity,
    MAX(CASE WHEN LOWER(drug) IN (
      'lorazepam', 'diazepam', 'midazolam', 'propofol', 'fentanyl'
    ) THEN 1 ELSE 0 END) AS has_cns_depressant,
    MAX(CASE WHEN LOWER(drug) IN (
      'vancomycin', 'gentamicin', 'ceftriaxone', 'contrast media'
    ) THEN 1 ELSE 0 END) AS has_nephrotoxic
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    drug IS NOT NULL
  GROUP BY
    hadm_id
),

grouped_patients AS (
  SELECT
    a.hadm_id,
    m.med_complexity,
    a.los,
    a.hospital_expire_flag,
    CASE
      WHEN m.has_cns_depressant = 1 AND m.has_nephrotoxic = 1 THEN 'Both'
      ELSE 'Other'
    END AS group_category
  FROM
    aki_patients a
  LEFT JOIN
    meds m
  ON
    a.hadm_id = m.hadm_id
  WHERE
    m.med_complexity IS NOT NULL
)

SELECT
  group_category,
  APPROX_QUANTILES(med_complexity, 4) AS complexity_quartiles,
  AVG(med_complexity) AS mean_complexity,
  AVG(los) AS avg_los,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(CASE WHEN los >= (
    SELECT APPROX_QUANTILES(los, 4)[OFFSET(3)]
    FROM grouped_patients
  ) THEN 1 ELSE 0 END) AS top_quartile_los_rate,
  AVG(CASE WHEN hospital_expire_flag = 1 AND los >= (
    SELECT APPROX_QUANTILES(los, 4)[OFFSET(3)]
    FROM grouped_patients
  ) THEN 1 ELSE 0 END) AS top_quartile_mortality_rate
FROM
  grouped_patients
GROUP BY
  group_category
ORDER BY
  group_category;