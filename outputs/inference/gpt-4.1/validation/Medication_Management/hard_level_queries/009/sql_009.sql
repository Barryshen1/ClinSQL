WITH aki_admissions AS (
  -- Step 1: Select female admissions aged 84-94 with AKI
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND (
      -- AKI ICD-9: 584.x, ICD-10: N17.x
      (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^584'))
      OR
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^N17'))
    )
),
med_complexity AS (
  -- Step 2: Medication complexity score per admission
  SELECT
    hadm_id,
    COUNT(DISTINCT LOWER(drug)) AS medication_complexity_score
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    hadm_id IN (SELECT hadm_id FROM aki_admissions)
  GROUP BY hadm_id
),
aki_admissions_with_complexity AS (
  -- Combine AKI admissions with medication complexity
  SELECT
    a.*,
    mc.medication_complexity_score
  FROM aki_admissions a
  LEFT JOIN med_complexity mc
    ON a.hadm_id = mc.hadm_id
),
aki_quintiles AS (
  -- Step 3: Assign quintiles by medication complexity score
  SELECT
    *,
    NTILE(5) OVER (ORDER BY medication_complexity_score) AS complexity_quintile
  FROM aki_admissions_with_complexity
),
los_and_mortality AS (
  -- Step 4 & 5: LOS and inpatient mortality per admission
  SELECT
    hadm_id,
    subject_id,
    complexity_quintile,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los,
    hospital_expire_flag
  FROM aki_quintiles
),
readmissions AS (
  -- Step 6: Find 30-day readmissions per admission
  SELECT
    a1.hadm_id,
    a1.subject_id,
    a1.complexity_quintile,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE
          a2.subject_id = a1.subject_id
          AND a2.admittime > a1.dischtime
          AND DATETIME_DIFF(a2.admittime, a1.dischtime, DAY) <= 30
      ) THEN 1
      ELSE 0
    END AS readmitted_30d
  FROM aki_quintiles a1
),
anticoagulant_opioid AS (
  -- Step 7: Find admissions with both anticoagulant and opioid prescriptions
  -- Drug lists (partial, can be expanded for completeness)
  -- Anticoagulants: warfarin, heparin, enoxaparin, apixaban, rivaroxaban, dabigatran, fondaparinux
  -- Opioids: morphine, oxycodone, hydromorphone, fentanyl, codeine, tramadol, methadone, buprenorphine
  SELECT
    hadm_id,
    MAX(is_anticoagulant) AS has_anticoagulant,
    MAX(is_opioid) AS has_opioid
  FROM (
    SELECT
      hadm_id,
      CASE
        WHEN LOWER(drug) LIKE '%warfarin%' THEN 1
        WHEN LOWER(drug) LIKE '%heparin%' THEN 1
        WHEN LOWER(drug) LIKE '%enoxaparin%' THEN 1
        WHEN LOWER(drug) LIKE '%apixaban%' THEN 1
        WHEN LOWER(drug) LIKE '%rivaroxaban%' THEN 1
        WHEN LOWER(drug) LIKE '%dabigatran%' THEN 1
        WHEN LOWER(drug) LIKE '%fondaparinux%' THEN 1
        ELSE 0
      END AS is_anticoagulant,
      CASE
        WHEN LOWER(drug) LIKE '%morphine%' THEN 1
        WHEN LOWER(drug) LIKE '%oxycodone%' THEN 1
        WHEN LOWER(drug) LIKE '%hydromorphone%' THEN 1
        WHEN LOWER(drug) LIKE '%fentanyl%' THEN 1
        WHEN LOWER(drug) LIKE '%codeine%' THEN 1
        WHEN LOWER(drug) LIKE '%tramadol%' THEN 1
        WHEN LOWER(drug) LIKE '%methadone%' THEN 1
        WHEN LOWER(drug) LIKE '%buprenorphine%' THEN 1
        ELSE 0
      END AS is_opioid
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE hadm_id IN (SELECT hadm_id FROM aki_quintiles)
  )
  GROUP BY hadm_id
),
coadmin_counts AS (
  -- Step 7b: Count admissions per quintile with both anticoagulant and opioid
  SELECT
    q.complexity_quintile,
    COUNT(*) AS anticoagulant_opioid_coadmin_count
  FROM aki_quintiles q
  JOIN anticoagulant_opioid ao ON q.hadm_id = ao.hadm_id
  WHERE ao.has_anticoagulant = 1 AND ao.has_opioid = 1
  GROUP BY q.complexity_quintile
),
final AS (
  -- Step 8: Aggregate per quintile
  SELECT
    l.complexity_quintile,
    COUNT(*) AS admission_count,
    AVG(l.los) AS avg_los,
    SUM(l.hospital_expire_flag) / COUNT(*) * 100 AS inpatient_mortality_pct,
    SUM(r.readmitted_30d) / COUNT(*) * 100 AS readmission_30d_pct
  FROM los_and_mortality l
  LEFT JOIN readmissions r ON l.hadm_id = r.hadm_id
  GROUP BY l.complexity_quintile
)
-- Final output: join with coadministration counts
SELECT
  f.complexity_quintile,
  f.admission_count,
  ROUND(f.avg_los, 2) AS avg_los,
  ROUND(f.inpatient_mortality_pct, 2) AS inpatient_mortality_pct,
  ROUND(f.readmission_30d_pct, 2) AS readmission_30d_pct,
  COALESCE(c.anticoagulant_opioid_coadmin_count, 0) AS anticoagulant_opioid_coadmin_count
FROM final f
LEFT JOIN coadmin_counts c
  ON f.complexity_quintile = c.complexity_quintile
ORDER BY f.complexity_quintile;