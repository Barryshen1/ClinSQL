WITH ami_admissions AS (
  -- admissions that include an acute myocardial infarction diagnosis
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%acute myocardial infarction%'
),

cohort_stays AS (
  -- ICU stays for male patients aged 76-86 whose admission had AMI
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    pt.anchor_age,
    pt.gender,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON icu.subject_id = pt.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  JOIN ami_admissions ami
    ON icu.hadm_id = ami.hadm_id
  WHERE pt.gender = 'M'
    AND pt.anchor_age BETWEEN 76 AND 86
),

procedure_counts AS (
  -- Count distinct procedure ICD codes per ICU stay occurring in the first 24 hours of the ICU stay.
  SELECT
    cs.subject_id,
    cs.hadm_id,
    cs.stay_id,
    cs.intime,
    cs.outtime,
    cs.los,
    cs.anchor_age,
    cs.gender,
    cs.hospital_expire_flag,
    COALESCE(COUNT(DISTINCT pr.icd_code), 0) AS procedure_count
  FROM cohort_stays cs
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON pr.hadm_id = cs.hadm_id
   AND pr.chartdate BETWEEN DATE(cs.intime) AND DATE_ADD(DATE(cs.intime), INTERVAL 1 DAY)
  GROUP BY
    cs.subject_id, cs.hadm_id, cs.stay_id, cs.intime, cs.outtime, cs.los,
    cs.anchor_age, cs.gender, cs.hospital_expire_flag
),

with_quartile AS (
  -- Assign quartiles based on procedure_count distribution (NTILE(4))
  SELECT
    pc.*,
    NTILE(4) OVER (ORDER BY procedure_count) AS quartile
  FROM procedure_counts pc
)

SELECT
  quartile,
  ROUND(AVG(procedure_count), 2) AS mean_procedure_count,
  ROUND(AVG(los), 2) AS mean_icu_los_days,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS hospital_mortality_pct,
  COUNT(*) AS n_stays
FROM with_quartile
GROUP BY quartile
ORDER BY quartile;