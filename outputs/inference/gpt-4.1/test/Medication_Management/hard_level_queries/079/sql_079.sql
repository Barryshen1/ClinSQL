WITH hemorrhagic_stroke_codes AS (
  -- ICD-10: I60*, I61*, I62*
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 10 AND (
      REGEXP_CONTAINS(icd_code, r'^I60') OR
      REGEXP_CONTAINS(icd_code, r'^I61') OR
      REGEXP_CONTAINS(icd_code, r'^I62')
    ))
    OR
    (icd_version = 9 AND (
      icd_code = '430' OR
      icd_code = '431' OR
      REGEXP_CONTAINS(icd_code, r'^432')
    ))
),
cohort AS (
  -- Select male patients aged 89-99 with hemorrhagic stroke
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    pat.anchor_age,
    pat.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  INNER JOIN hemorrhagic_stroke_codes codes
    ON dx.icd_code = codes.icd_code AND dx.icd_version = codes.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 89 AND 99
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
),
med_complexity AS (
  -- Count unique drugs in first 7 days of admission
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT pr.drug) AS medication_complexity,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
    AND pr.starttime >= c.admittime
    AND pr.starttime < DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
    AND pr.drug IS NOT NULL
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag
),
quintiles AS (
  -- Assign quintile by medication complexity
  SELECT
    *,
    NTILE(5) OVER (ORDER BY medication_complexity) AS complexity_quintile
  FROM med_complexity
),
readmissions AS (
  -- For each index admission, check for readmission within 30 days
  SELECT
    q.subject_id,
    q.hadm_id,
    MIN(next_adm.admittime) AS next_admittime,
    q.dischtime,
    CASE
      WHEN MIN(next_adm.admittime) IS NOT NULL
           AND TIMESTAMP_DIFF(MIN(next_adm.admittime), q.dischtime, DAY) <= 30
      THEN 1 ELSE 0
    END AS readmitted_30d
  FROM quintiles q
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` next_adm
    ON q.subject_id = next_adm.subject_id
    AND next_adm.admittime > q.dischtime
    AND TIMESTAMP_DIFF(next_adm.admittime, q.dischtime, DAY) <= 30
  GROUP BY q.subject_id, q.hadm_id, q.dischtime
),
final AS (
  -- Combine all metrics
  SELECT
    q.complexity_quintile,
    COUNT(*) AS num_admissions,
    AVG(TIMESTAMP_DIFF(q.dischtime, q.admittime, DAY)) AS avg_los_days,
    AVG(CAST(q.hospital_expire_flag AS FLOAT64)) AS inpatient_mortality_rate,
    AVG(CAST(r.readmitted_30d AS FLOAT64)) AS readmission_30d_rate
  FROM quintiles q
  LEFT JOIN readmissions r
    ON q.subject_id = r.subject_id AND q.hadm_id = r.hadm_id
  WHERE q.hospital_expire_flag = 0 -- Only include survivors for readmission rate
  GROUP BY q.complexity_quintile
  ORDER BY q.complexity_quintile
)

SELECT
  complexity_quintile,
  num_admissions,
  avg_los_days,
  inpatient_mortality_rate,
  readmission_30d_rate
FROM final
ORDER BY complexity_quintile;