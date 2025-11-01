WITH cardiogenic_adms AS (
  -- admissions that have a diagnosis whose description mentions "cardiogenic shock"
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE LOWER(COALESCE(dd.long_title, '')) LIKE '%cardiogenic shock%'
),

cohort_stays AS (
  -- ICU stays for male patients aged 82-92 whose admission had cardiogenic shock
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.subject_id = adm.subject_id AND icu.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
    AND icu.hadm_id IN (SELECT hadm_id FROM cardiogenic_adms)
    -- require non-null admission/discharge to compute LOS and mortality reliably
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
),

proc_counts AS (
  -- count procedureevents in the first 24 hours of each ICU stay (include zero counts)
  SELECT
    cs.subject_id,
    cs.hadm_id,
    cs.stay_id,
    cs.intime,
    cs.admittime,
    cs.dischtime,
    cs.hospital_expire_flag,
    cs.anchor_age,
    TIMESTAMP_DIFF(cs.dischtime, cs.admittime, SECOND) / 86400.0 AS los_days,
    COUNT(pe.starttime) AS proc_count
  FROM cohort_stays cs
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON pe.stay_id = cs.stay_id
    AND pe.starttime BETWEEN cs.intime AND TIMESTAMP_ADD(cs.intime, INTERVAL 24 HOUR)
  GROUP BY
    cs.subject_id, cs.hadm_id, cs.stay_id, cs.intime, cs.admittime, cs.dischtime, cs.hospital_expire_flag, cs.anchor_age
),

ranked AS (
  -- assign quintiles by procedure count
  SELECT
    *,
    NTILE(5) OVER (ORDER BY proc_count) AS quintile
  FROM proc_counts
)

SELECT
  quintile,
  ROUND(AVG(proc_count), 3) AS mean_proc_count,
  ROUND(AVG(los_days), 3) AS mean_hospital_los_days,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100, 2) AS in_hospital_mortality_pct,
  COUNT(*) AS n_stays
FROM ranked
GROUP BY quintile
ORDER BY quintile;