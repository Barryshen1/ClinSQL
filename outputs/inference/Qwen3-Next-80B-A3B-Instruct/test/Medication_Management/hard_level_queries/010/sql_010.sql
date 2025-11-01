WITH stroke_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.dischtime,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 61 AND 71
    AND d.icd_version = 10
    AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%')
),

first_icu_stay AS (
  SELECT
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS rn
  FROM physionet-data.mimiciv_3_1_icu.icustays i
),

med_complexity AS (
  SELECT
    f.stay_id,
    COUNT(DISTINCT p.drug) AS med_complexity_score
  FROM first_icu_stay f
  INNER JOIN physionet-data.mimiciv_3_1_hosp.prescriptions p
    ON f.hadm_id = p.hadm_id
  WHERE p.starttime >= f.intime
    AND p.starttime <= DATETIME_ADD(f.intime, INTERVAL 24 HOUR)
    AND f.rn = 1
  GROUP BY f.stay_id
),

readmission_flag AS (
  SELECT
    a1.hadm_id,
    CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmission_30d_flag
  FROM stroke_patients a1
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.admissions a2
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND a2.admittime <= DATETIME_ADD(a1.dischtime, INTERVAL 30 DAY)
),

combined AS (
  SELECT
    mc.stay_id,
    mc.med_complexity_score,
    f.los,
    sp.hospital_expire_flag,
    COALESCE(r.readmission_30d_flag, 0) AS readmission_30d_flag
  FROM med_complexity mc
  INNER JOIN first_icu_stay f ON mc.stay_id = f.stay_id
  INNER JOIN stroke_patients sp ON f.hadm_id = sp.hadm_id
  LEFT JOIN readmission_flag r ON sp.hadm_id = r.hadm_id
),

quintiles AS (
  SELECT
    med_complexity_score,
    los,
    hospital_expire_flag,
    readmission_30d_flag,
    NTILE(5) OVER (ORDER BY med_complexity_score) AS quintile
  FROM combined
)

SELECT
  quintile,
  COUNT(*) AS number_of_patients,
  AVG(med_complexity_score) AS mean_complexity_score,
  AVG(los) AS average_los,
  AVG(hospital_expire_flag) AS in_hospital_mortality,
  AVG(readmission_30d_flag) AS thirty_day_readmission_rate
FROM quintiles
GROUP BY quintile
ORDER BY quintile;