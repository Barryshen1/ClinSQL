WITH admissions_filtered AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.anchor_age BETWEEN 77 AND 87
    AND p.gender = 'F'
),

-- Identify ACS admissions
acs_admissions AS (
  SELECT DISTINCT
    d.hadm_id,
    d.seq_num
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    (d.icd_version = 9 AND d.icd_code LIKE '410%')
    OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
),

-- Radiography/CT procedures
radiology_procedures AS (
  SELECT DISTINCT
    p.hadm_id,
    p.seq_num
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
  ON
    p.icd_code = dp.icd_code
    AND p.icd_version = dp.icd_version
  WHERE
    (p.icd_version = 9 AND p.icd_code IN ('87', '1')) -- 87 = CT, 1 = diagnostic radiology
    OR (p.icd_version = 10 AND p.icd_code LIKE 'B22%') -- example ICD-10 for imaging
),

-- Combine admissions, ACS, and radiology
admission_radiology_counts AS (
  SELECT
    af.hadm_id,
    aa.seq_num AS diagnosis_seq,
    CASE
      WHEN af.los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN af.los_days BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group,
    COUNT(rp.seq_num) AS radiology_count
  FROM
    admissions_filtered af
  JOIN
    acs_admissions aa
  ON
    af.hadm_id = aa.hadm_id
  LEFT JOIN
    radiology_procedures rp
  ON
    af.hadm_id = rp.hadm_id
  WHERE
    af.los_days BETWEEN 1 AND 8
  GROUP BY
    af.hadm_id, aa.seq_num, los_group
)

-- Final aggregation
SELECT
  los_group,
  CASE
    WHEN diagnosis_seq = 1 THEN 'Primary'
    ELSE 'Secondary'
  END AS diagnosis_position,
  AVG(radiology_count) AS mean_count,
  MIN(radiology_count) AS min_count,
  MAX(radiology_count) AS max_count
FROM
  admission_radiology_counts
GROUP BY
  los_group,
  diagnosis_position
ORDER BY
  los_group,
  diagnosis_position;