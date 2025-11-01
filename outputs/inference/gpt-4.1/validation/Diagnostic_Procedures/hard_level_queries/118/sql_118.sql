WITH cohort AS (
  -- Identify female ICU patients aged 44-54 with AMI diagnosis
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime AS icu_intime,
    icu.outtime AS icu_outtime,
    pat.anchor_age,
    pat.gender
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
    JOIN (
      -- AMI diagnosis: ICD-9 410.*, ICD-10 I21.*, I22.*
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE
        (diag.icd_version = 9 AND diag.icd_code LIKE '410%')
        OR (diag.icd_version = 10 AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%'))
    ) ami
      ON icu.hadm_id = ami.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 44 AND 54
),
first_icu_stay AS (
  -- Get first ICU stay per hospital admission
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    icu_intime,
    icu_outtime
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY icu_intime) AS rn
    FROM cohort
  )
  WHERE rn = 1
),
icu_proc_count AS (
  -- Count ICU procedures in first 72h of ICU stay
  SELECT
    f.subject_id,
    f.hadm_id,
    COUNT(*) AS icu_proc_count
  FROM first_icu_stay f
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      ON f.subject_id = pe.subject_id
      AND f.hadm_id = pe.hadm_id
      AND f.stay_id = pe.stay_id
      AND pe.starttime >= f.icu_intime
      AND pe.starttime < DATETIME_ADD(f.icu_intime, INTERVAL 72 HOUR)
  GROUP BY f.subject_id, f.hadm_id
),
hosp_proc_count AS (
  -- Count hospital procedures in first 72h of ICU stay
  SELECT
    f.subject_id,
    f.hadm_id,
    COUNT(pr.icd_code) AS hosp_proc_count
  FROM first_icu_stay f
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
      ON f.subject_id = pr.subject_id
      AND f.hadm_id = pr.hadm_id
      AND pr.chartdate >= DATE(f.icu_intime)
      AND pr.chartdate < DATE_ADD(DATE(f.icu_intime), INTERVAL 3 DAY)
  GROUP BY f.subject_id, f.hadm_id
),
proc_burden AS (
  -- Sum ICU and hospital procedures
  SELECT
    f.subject_id,
    f.hadm_id,
    COALESCE(i.icu_proc_count, 0) + COALESCE(h.hosp_proc_count, 0) AS procedure_count
  FROM first_icu_stay f
    LEFT JOIN icu_proc_count i
      ON f.subject_id = i.subject_id AND f.hadm_id = i.hadm_id
    LEFT JOIN hosp_proc_count h
      ON f.subject_id = h.subject_id AND f.hadm_id = h.hadm_id
),
final AS (
  -- Add LOS and mortality
  SELECT
    p.subject_id,
    p.hadm_id,
    p.procedure_count,
    a.dischtime,
    a.admittime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los
  FROM proc_burden p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
),
quartiled AS (
  -- Assign quartiles by procedure count
  SELECT
    *,
    NTILE(4) OVER (ORDER BY procedure_count) AS proc_quartile
  FROM final
)
SELECT
  proc_quartile AS procedure_burden_quartile,
  COUNT(*) AS n_patients,
  ROUND(AVG(procedure_count),2) AS mean_procedure_count,
  ROUND(AVG(hospital_los),2) AS mean_hospital_los_days,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*),2) AS in_hospital_mortality_percent
FROM quartiled
GROUP BY proc_quartile
ORDER BY proc_quartile;