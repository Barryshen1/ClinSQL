WITH troponin_first AS (
  SELECT
    le.hadm_id,
    le.valuenum,
    le.charttime,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC) AS rn
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents le
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems di
    ON le.itemid = di.itemid
  WHERE
    LOWER(di.label) = 'troponin t'
    AND le.valuenum IS NOT NULL
),
acs_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    -- ICD-10 codes for ACS: I20-I25 (approximate range)
    (
      (d.icd_version = 10 AND d.icd_code BETWEEN 'I20' AND 'I259')
      OR
      (d.icd_version = 9 AND d.icd_code BETWEEN '410' AND '41499')
    )
),
filtered_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
),
valid_troponin AS (
  SELECT
    tf.hadm_id,
    tf.valuenum
  FROM
    troponin_first tf
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON tf.hadm_id = a.hadm_id
  WHERE
    tf.rn = 1
    AND tf.valuenum IS NOT NULL
    AND tf.charttime BETWEEN a.admittime AND a.dischtime
),
combined_data AS (
  SELECT
    fp.hadm_id,
    fp.hospital_expire_flag,
    CASE
      WHEN vt.valuenum <= 0.04 THEN 'Normal (≤0.04)'
      WHEN vt.valuenum > 0.04 AND vt.valuenum <= 0.1 THEN 'Borderline (>0.04–0.1)'
      WHEN vt.valuenum > 0.1 THEN 'Elevated (>0.1)'
      ELSE 'Other'
    END AS troponin_group
  FROM
    filtered_patients fp
  JOIN
    acs_admissions aa
    ON fp.hadm_id = aa.hadm_id
  JOIN
    valid_troponin vt
    ON fp.hadm_id = vt.hadm_id
),
grouped_stats AS (
  SELECT
    troponin_group,
    COUNT(*) AS admission_count,
    SUM(hospital_expire_flag) AS death_count
  FROM
    combined_data
  GROUP BY
    troponin_group
),
total_admissions AS (
  SELECT COUNT(*) AS total FROM combined_data
)
SELECT
  gs.troponin_group,
  gs.admission_count,
  ROUND(gs.admission_count * 100.0 / ta.total, 2) AS percent_of_total,
  ROUND(gs.death_count * 100.0 / gs.admission_count, 2) AS in_hospital_mortality_percent
FROM
  grouped_stats gs
CROSS JOIN
  total_admissions ta
ORDER BY
  CASE gs.troponin_group
    WHEN 'Normal (≤0.04)' THEN 1
    WHEN 'Borderline (>0.04–0.1)' THEN 2
    WHEN 'Elevated (>0.1)' THEN 3
    ELSE 4
  END;