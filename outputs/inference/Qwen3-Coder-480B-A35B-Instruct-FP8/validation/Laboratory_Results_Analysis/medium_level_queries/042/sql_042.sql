WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND LOWER(dd.long_title) LIKE '%chest pain%'
),

first_troponin AS (
  SELECT
    l.hadm_id,
    l.valuenum AS troponin_value,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
  ON
    l.itemid = d.itemid
  WHERE
    LOWER(d.label) = 'troponin t'
    AND l.valuenum IS NOT NULL
),

troponin_category AS (
  SELECT
    hadm_id,
    CASE
      WHEN troponin_value <= 0.01 THEN 'Normal'
      WHEN troponin_value <= 0.039 THEN 'Borderline'
      ELSE 'Elevated'
    END AS troponin_group
  FROM
    first_troponin
  WHERE
    rn = 1
)

SELECT
  tc.troponin_group,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  SUM(c.hospital_expire_flag) AS in_hospital_deaths,
  ROUND(SUM(c.hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate
FROM
  cohort c
JOIN
  troponin_category tc
ON
  c.hadm_id = tc.hadm_id
GROUP BY
  tc.troponin_group
ORDER BY
  CASE tc.troponin_group
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
  END;