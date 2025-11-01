WITH patients_filtered AS (
  SELECT p.subject_id, p.gender, p.anchor_age, p.anchor_year,
         EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admit,
         a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 78 AND 88
    AND a.dischtime IS NOT NULL
),

cardiac_arrest_admissions AS (
  SELECT DISTINCT pfa.*
  FROM patients_filtered pfa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pfa.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_code LIKE 'I46%'
),

medications_first_7_days AS (
  SELECT p.hadm_id,
         p.drug,
         LOWER(p.route) AS route,
         -- Define high-risk drugs by keyword
         CASE
           WHEN LOWER(p.drug) LIKE '%warfarin%' OR
                LOWER(p.drug) LIKE '%insulin%' OR
                LOWER(p.drug) LIKE '%digoxin%' OR
                LOWER(p.drug) LIKE '%phenytoin%' OR
                LOWER(p.drug) LIKE '%lithium%' OR
                LOWER(p.drug) LIKE '%heparin%' OR
                LOWER(p.drug) LIKE '%enoxaparin%' OR
                LOWER(p.drug) LIKE '%apixaban%' OR
                LOWER(p.drug) LIKE '%rivaroxaban%' OR
                LOWER(p.drug) LIKE '%dabigatran%' OR
                LOWER(p.drug) LIKE '%clopidogrel%' OR
                LOWER(p.drug) LIKE '%ticagrelor%' OR
                LOWER(p.drug) LIKE '%amiodarone%' OR
                LOWER(p.drug) LIKE '%fentanyl%' OR
                LOWER(p.drug) LIKE '%hydromorphone%' OR
                LOWER(p.drug) LIKE '%morphine%'
             THEN 1
           ELSE 0
         END AS is_high_risk
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions p
  INNER JOIN cardiac_arrest_admissions ca
    ON p.hadm_id = ca.hadm_id
  WHERE p.starttime IS NOT NULL
    AND p.starttime >= ca.admittime
    AND p.starttime < DATETIME_ADD(ca.admittime, INTERVAL 7 DAY)
),

med_score_per_admission AS (
  SELECT hadm_id,
         COUNT(DISTINCT drug) AS unique_drugs,
         SUM(is_high_risk) AS high_risk_count,
         COUNT(DISTINCT route) AS unique_routes,
         COUNT(DISTINCT drug) + 2 * SUM(is_high_risk) + COUNT(DISTINCT route) AS complexity_score
  FROM medications_first_7_days
  GROUP BY hadm_id
),

tertiles AS (
  SELECT ca.*,
         COALESCE(ms.complexity_score, 0) AS complexity_score,
         NTILE(3) OVER (ORDER BY COALESCE(ms.complexity_score, 0)) AS tertile
  FROM cardiac_arrest_admissions ca
  LEFT JOIN med_score_per_admission ms ON ca.hadm_id = ms.hadm_id
),

readmissions AS (
  SELECT t.*,
         LEAD(t.admittime) OVER (PARTITION BY t.subject_id ORDER BY t.admittime) AS next_admittime
  FROM tertiles t
),

readmission_flags AS (
  SELECT *,
         CASE
           WHEN next_admittime IS NOT NULL
                AND DATETIME_DIFF(next_admittime, dischtime, DAY) <= 30
           THEN 1
           ELSE 0
         END AS thirty_day_readmit
  FROM readmissions
),

hospital_los AS (
  SELECT *,
         DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0 AS los_days
  FROM readmission_flags
)

SELECT
  tertile,
  COUNT(*) AS patient_count,
  MIN(complexity_score) AS min_score,
  MAX(complexity_score) AS max_score,
  ROUND(AVG(complexity_score), 2) AS avg_score,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_pct,
  ROUND(100.0 * SUM(thirty_day_readmit) / COUNT(*), 2) AS thirty_day_readmission_pct
FROM hospital_los
GROUP BY tertile
ORDER BY tertile;