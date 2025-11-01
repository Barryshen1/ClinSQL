WITH surgical_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    icu.hadm_id,
    icu.stay_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    icu.intime,
    icu.outtime,
    icu.los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON a.hadm_id = icu.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON a.hadm_id = pr.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpr
    ON pr.icd_code = dpr.icd_code
    AND pr.icd_version = dpr.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND UPPER(dpr.long_title) LIKE '%SURG%'
),
med_complexity AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    COUNT(DISTINCT prx.drug) AS med_complexity
  FROM surgical_cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` prx
    ON c.hadm_id = prx.hadm_id
    AND prx.starttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
  GROUP BY c.subject_id, c.hadm_id, c.stay_id
),
quintiles AS (
  SELECT
    mc.*,
    NTILE(5) OVER (ORDER BY med_complexity) AS complexity_quintile
  FROM med_complexity mc
),
readmission AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    CASE 
      WHEN MIN(ra.admittime) <= DATETIME_ADD(MIN(a.dischtime), INTERVAL 30 DAY)
           AND MIN(ra.admittime) > MIN(a.dischtime)
      THEN 1 ELSE 0 
    END AS readmit_30d
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ra
    ON a.subject_id = ra.subject_id
    AND ra.hadm_id <> a.hadm_id
    AND ra.admittime > a.dischtime
  GROUP BY a.subject_id, a.hadm_id
),
cohort_with_quintile AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.anchor_age,
    q.med_complexity,
    q.complexity_quintile,
    c.los,
    c.hospital_expire_flag,
    r.readmit_30d
  FROM surgical_cohort c
  JOIN quintiles q
    ON c.subject_id = q.subject_id
    AND c.stay_id = q.stay_id
  LEFT JOIN readmission r
    ON c.subject_id = r.subject_id
    AND c.hadm_id = r.hadm_id
),
agg_per_quintile AS (
  SELECT
    complexity_quintile,
    COUNT(*) AS n_stays,
    AVG(los) AS avg_icu_los_days,
    AVG(hospital_expire_flag) AS inhospital_mortality_rate,
    AVG(readmit_30d) AS readmit_30d_rate
  FROM cohort_with_quintile
  GROUP BY complexity_quintile
)
SELECT
  a.*,
  idx.med_complexity AS index_patient_med_complexity,
  idx.complexity_quintile AS index_patient_quintile,
  qavg.avg_icu_los_days AS index_patient_quintile_avg_los,
  qavg.inhospital_mortality_rate AS index_patient_quintile_mortality,
  qavg.readmit_30d_rate AS index_patient_quintile_readmit_rate
FROM agg_per_quintile a
JOIN (
  -- pick index patient: 42yo male postoperative ICU (first match)
  SELECT *
  FROM cohort_with_quintile
  WHERE anchor_age = 42
  LIMIT 1
) idx
  ON a.complexity_quintile = idx.complexity_quintile
JOIN agg_per_quintile qavg
  ON idx.complexity_quintile = qavg.complexity_quintile
ORDER BY complexity_quintile;