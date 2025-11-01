WITH tia_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group,
    MAX(CASE WHEN icu.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS icu_used
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
  LEFT JOIN
    physionet-data.mimiciv_3_1_icu.icustays icu
    ON a.hadm_id = icu.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 72 AND 82
    AND di.seq_num = 1
    AND LOWER(d.long_title) = 'transient ischemic attack'
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
  GROUP BY
    a.hadm_id, a.subject_id, a.admittime, a.dischtime
),

imaging_counts AS (
  SELECT
    ta.hadm_id,
    COUNT(proc.hadm_id) AS imaging_proc_count
  FROM
    tia_admissions ta
  LEFT JOIN
    physionet-data.mimiciv_3_1_hosp.procedures_icd proc
    ON ta.hadm_id = proc.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dproc
    ON proc.icd_code = dproc.icd_code AND proc.icd_version = dproc.icd_version
  WHERE
    REGEXP_CONTAINS(LOWER(dproc.long_title), r'(imag|radiolog)')
  GROUP BY
    ta.hadm_id
)

SELECT
  ta.los_group,
  CASE WHEN ta.icu_used = 1 THEN 'Yes' ELSE 'No' END AS icu_used,
  COUNT(*) AS admission_count,
  AVG(COALESCE(ic.imaging_proc_count, 0)) AS mean_imaging_procedures_per_admission
FROM
  tia_admissions ta
LEFT JOIN
  imaging_counts ic
  ON ta.hadm_id = ic.hadm_id
GROUP BY
  ta.los_group,
  ta.icu_used
ORDER BY
  ta.los_group,
  ta.icu_used;