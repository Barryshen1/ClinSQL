WITH admissions_filtered AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_category,
    di.seq_num,
    CASE
      WHEN di.seq_num = 1 THEN 'primary'
      ELSE 'secondary'
    END AS diagnosis_type
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND LOWER(d.long_title) LIKE '%acute pancreatitis%'
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
),

procedures_per_admission AS (
  SELECT
    af.hadm_id,
    af.los_category,
    af.diagnosis_type,
    COUNT(pr.icd_code) AS proc_count
  FROM
    admissions_filtered af
  JOIN
    physionet-data.mimiciv_3_1_hosp.procedures_icd pr
    ON af.hadm_id = pr.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dp
    ON pr.icd_code = dp.icd_code AND pr.icd_version = dp.icd_version
  WHERE
    LOWER(dp.long_title) LIKE '%diagnostic%'
  GROUP BY
    af.hadm_id, af.los_category, af.diagnosis_type
)

SELECT
  los_category,
  diagnosis_type,
  AVG(proc_count) AS mean_procedures,
  MIN(proc_count) AS min_procedures,
  MAX(proc_count) AS max_procedures
FROM
  procedures_per_admission
GROUP BY
  los_category,
  diagnosis_type
ORDER BY
  los_category,
  diagnosis_type;