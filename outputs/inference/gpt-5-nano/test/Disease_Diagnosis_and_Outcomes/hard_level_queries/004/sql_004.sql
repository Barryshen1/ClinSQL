WITH ich_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    -- Age at admission: anchor_age + (admit_year - anchor_year)
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 44 AND 54
    -- Intracranial hemorrhage: ICD-10 I60-I62 or ICD-9 430-432
    AND (
          (di.icd_version = 10 AND (di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%' OR di.icd_code LIKE 'I62%'))
          OR
          (di.icd_version = 9  AND (di.icd_code LIKE '430%' OR di.icd_code LIKE '431%' OR di.icd_code LIKE '432%'))
        )
),
adm_with_los AS (
  SELECT i.subject_id, i.hadm_id,
         a.admittime, a.dischtime,
         a.hospital_expire_flag,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM ich_admissions i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
),
diag_agg AS (
  SELECT a.subject_id, a.hadm_id,
         a.admittime, a.dischtime, a.hospital_expire_flag, a.los_days,
         COUNT(*) AS diag_count,
         MAX(CASE
               -- Cardiac complications: ICD-9 410/411/428; ICD-10 I21/I22/I50
               WHEN ((d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code LIKE '411%' OR d.icd_code LIKE '428%'))
                     OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' OR d.icd_code LIKE 'I50%')))
               THEN 1 ELSE 0 END) AS has_cardio,
         MAX(CASE
               -- Neurologic complications: ICD-9 430-434-436 patterns; ICD-10 I60-I62, G40/G41
               WHEN ((d.icd_version = 9 AND (d.icd_code LIKE '430%' OR d.icd_code LIKE '431%' OR d.icd_code LIKE '432%' OR d.icd_code LIKE '434%' OR d.icd_code LIKE '435%' OR d.icd_code LIKE '436%'))
                     OR (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%' OR d.icd_code LIKE 'G40%' OR d.icd_code LIKE 'G41%')))
               THEN 1 ELSE 0 END) AS has_neuro
  FROM adm_with_los a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, a.los_days
),
quartile AS (
  SELECT *,
         NTILE(4) OVER (ORDER BY diag_count) AS risk_quartile
  FROM diag_agg
)
SELECT
  risk_quartile AS quartile,
  COUNT(DISTINCT subject_id) AS patient_count,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_mortality,
  SUM(has_cardio) AS cardiac_complications,
  SUM(has_neuro) AS neuro_complications,
  APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los_days END, 2)[OFFSET(1)] AS median_los_survivors_days
FROM quartile
GROUP BY quartile
ORDER BY quartile;