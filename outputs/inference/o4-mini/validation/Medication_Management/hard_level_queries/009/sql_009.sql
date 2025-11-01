WITH
-- 1. Base cohort: female, age 84-89 (MIMIC top-codes >89 to 89)
base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 89
),
-- 2. Restrict to AKI
aki_adm AS (
  SELECT DISTINCT b.*
  FROM base b
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON b.subject_id = d.subject_id
   AND b.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%acute kidney injury%'
),
-- 3. Medication complexity: distinct drugs per admission
med_complex AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT drug) AS complexity_score
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE hadm_id IN (SELECT hadm_id FROM aki_adm)
  GROUP BY hadm_id
),
-- 4. Quintiles
with_quintile AS (
  SELECT
    a.*,
    mc.complexity_score,
    NTILE(5) OVER (ORDER BY mc.complexity_score) AS complexity_quintile
  FROM aki_adm a
  LEFT JOIN med_complex mc
    ON a.hadm_id = mc.hadm_id
),
-- 5. 30-day readmission flag
readmit AS (
  SELECT
    subject_id,
    hadm_id,
    dischtime,
    LEAD(admittime) OVER (
      PARTITION BY subject_id
      ORDER BY admittime
    ) AS next_admit
  FROM with_quintile
),
readmit_flag AS (
  SELECT
    wq.*,
    CASE
      WHEN r.next_admit IS NOT NULL
        AND TIMESTAMP_DIFF(r.next_admit, r.dischtime, DAY) <= 30
      THEN 1 ELSE 0
    END AS readmit30
  FROM with_quintile wq
  JOIN readmit r
    ON wq.subject_id = r.subject_id
   AND wq.hadm_id = r.hadm_id
),
-- 6a. Opioid prescriptions (example list)
opioid_pres AS (
  SELECT
    subject_id,
    hadm_id,
    starttime,
    stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE drug IN (
    'OXYCODONE', 'MORPHINE', 'HYDROMORPHONE', 'FENTANYL'
  )
    AND hadm_id IN (SELECT hadm_id FROM readmit_flag)
),
-- 6b. Anticoagulant prescriptions (example list)
anticoag_pres AS (
  SELECT
    subject_id,
    hadm_id,
    starttime,
    stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE drug IN (
    'HEPARIN', 'ENOXAPARIN', 'WARFARIN', 'APIXABAN', 'RIVAROXABAN'
  )
    AND hadm_id IN (SELECT hadm_id FROM readmit_flag)
),
-- 6c. Identify overlapping intervals per hadm_id
coadmin_flag AS (
  SELECT
    r.subject_id,
    r.hadm_id,
    CASE WHEN COUNT(1) > 0 THEN 1 ELSE 0 END AS coadmin
  FROM readmit_flag r
  LEFT JOIN opioid_pres o
    ON r.hadm_id = o.hadm_id
  LEFT JOIN anticoag_pres a
    ON r.hadm_id = a.hadm_id
    -- overlap condition
    AND o.starttime < a.stoptime
    AND a.starttime < o.stoptime
  GROUP BY r.subject_id, r.hadm_id
)
-- 7. Final aggregation by quintile
SELECT
  q.complexity_quintile,
  COUNT(1) AS n_admissions,
  ROUND(AVG(q.los), 1) AS avg_los_days,
  ROUND(100 * SUM(q.hospital_expire_flag) / COUNT(1), 1) AS pct_in_hosp_mortality,
  ROUND(100 * SUM(q.readmit30) / COUNT(1), 1) AS pct_30d_readmission,
  SUM(cf.coadmin) AS n_coadmin_admissions
FROM readmit_flag q
JOIN coadmin_flag cf
  ON q.hadm_id = cf.hadm_id
GROUP BY q.complexity_quintile
ORDER BY q.complexity_quintile;