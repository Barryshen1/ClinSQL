WITH vasopressor_itemids AS (
  -- List of common vasopressor itemids in inputevents (from d_items)
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) IN (
    'norepinephrine', 'noradrenaline', 'epinephrine', 'adrenaline',
    'vasopressin', 'dopamine', 'phenylephrine', 'metaraminol'
  )
),
cohort AS (
  -- Step 1: Identify male ICU patients aged 68-78 with vasopressor within 72h
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 68 AND 78
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.inputevents` inp
      JOIN vasopressor_itemids v ON inp.itemid = v.itemid
      WHERE inp.subject_id = icu.subject_id
        AND inp.hadm_id = icu.hadm_id
        AND inp.stay_id = icu.stay_id
        AND inp.starttime >= icu.intime
        AND inp.starttime < DATETIME_ADD(icu.intime, INTERVAL 72 HOUR)
    )
),
diagnostic_counts AS (
  -- Step 2: For each ICU stay, count labs + imaging in first 72h
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.outtime,
    c.anchor_age,
    c.gender,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    -- Labs
    (
      SELECT COUNT(*) FROM `physionet-data.mimiciv_3_1_hosp.labevents` lab
      WHERE lab.subject_id = c.subject_id
        AND lab.hadm_id = c.hadm_id
        AND lab.charttime >= c.intime
        AND lab.charttime < DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    ) AS lab_count,
    -- Imaging procedures
    (
      SELECT COUNT(*)
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dproc
        ON proc.icd_code = dproc.icd_code AND proc.icd_version = dproc.icd_version
      WHERE proc.subject_id = c.subject_id
        AND proc.hadm_id = c.hadm_id
        AND proc.chartdate >= DATE(c.intime)
        AND proc.chartdate < DATE(DATETIME_ADD(c.intime, INTERVAL 72 HOUR))
        AND (
          LOWER(dproc.long_title) LIKE '%radiology%'
          OR LOWER(dproc.long_title) LIKE '%ct%'
          OR LOWER(dproc.long_title) LIKE '%mri%'
          OR LOWER(dproc.long_title) LIKE '%ultrasound%'
          OR LOWER(dproc.long_title) LIKE '%x-ray%'
        )
    ) AS imaging_count
  FROM cohort c
),
diagnostic_load AS (
  -- Step 3: Sum labs + imaging, assign quartile
  SELECT
    *,
    (lab_count + imaging_count) AS diagnostic_count,
    NTILE(4) OVER (ORDER BY (lab_count + imaging_count)) AS diagnostic_quartile
  FROM diagnostic_counts
),
readmissions AS (
  -- Step 4: For each discharge, check for readmission within 30 days
  SELECT
    a.subject_id,
    a.hadm_id,
    a.dischtime,
    MIN(next_adm.admittime) AS next_admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` next_adm
    ON a.subject_id = next_adm.subject_id
    AND next_adm.admittime > a.dischtime
    AND next_adm.admittime <= DATETIME_ADD(a.dischtime, INTERVAL 30 DAY)
  GROUP BY a.subject_id, a.hadm_id, a.dischtime
),
final AS (
  SELECT
    dl.diagnostic_quartile,
    COUNT(*) AS n_stays,
    AVG(dl.diagnostic_count) AS avg_diagnostic_count,
    AVG(TIMESTAMP_DIFF(dl.dischtime, dl.admittime, HOUR)/24.0) AS avg_hospital_los_days,
    AVG(CAST(dl.hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality_rate,
    AVG(CASE WHEN r.next_admittime IS NOT NULL THEN 1 ELSE 0 END) AS readmission_30day_rate
  FROM diagnostic_load dl
  LEFT JOIN readmissions r
    ON dl.subject_id = r.subject_id AND dl.hadm_id = r.hadm_id AND dl.dischtime = r.dischtime
  GROUP BY dl.diagnostic_quartile
  ORDER BY dl.diagnostic_quartile
)
SELECT
  diagnostic_quartile,
  n_stays,
  avg_diagnostic_count,
  avg_hospital_los_days,
  in_hospital_mortality_rate,
  readmission_30day_rate
FROM final
ORDER BY diagnostic_quartile;