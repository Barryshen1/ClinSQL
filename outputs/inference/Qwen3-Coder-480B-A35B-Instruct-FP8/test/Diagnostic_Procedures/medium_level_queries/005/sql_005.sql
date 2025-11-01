WITH ischemic_stroke_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group,
    di.seq_num,
    CASE
      WHEN di.seq_num = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS diagnosis_type
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
    AND LOWER(d.long_title) LIKE '%ischemic stroke%'
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
),

procedure_counts AS (
  SELECT
    isa.hadm_id,
    isa.los_group,
    isa.diagnosis_type,
    COUNT(pr.icd_code) AS proc_count
  FROM
    ischemic_stroke_admissions isa
  LEFT JOIN
    physionet-data.mimiciv_3_1_hosp.procedures_icd pr
    ON isa.hadm_id = pr.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dp
    ON pr.icd_code = dp.icd_code AND pr.icd_version = dp.icd_version
  WHERE
    LOWER(dp.long_title) LIKE '%diagnostic%'
  GROUP BY
    isa.hadm_id, isa.los_group, isa.diagnosis_type
)

SELECT
  los_group,
  diagnosis_type,
  AVG(proc_count) AS mean_procedures,
  MIN(proc_count) AS min_procedures,
  MAX(proc_count) AS max_procedures
FROM
  procedure_counts
GROUP BY
  los_group, diagnosis_type
ORDER BY
  los_group, diagnosis_type;