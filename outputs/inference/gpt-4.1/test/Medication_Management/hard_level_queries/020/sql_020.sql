WITH cardiac_arrest_codes AS (
  -- ICD-9: 427.5, ICD-10: I46.x
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND icd_code = '4275')
     OR (icd_version = 10 AND (icd_code LIKE 'I46%' OR icd_code = 'I469'))
),
index_admissions AS (
  -- Female, age 78-88, with cardiac arrest diagnosis
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    pat.anchor_age,
    pat.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  JOIN cardiac_arrest_codes cac
    ON dx.icd_code = cac.icd_code AND dx.icd_version = cac.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 78 AND 88
),
meds_7d AS (
  -- Medications prescribed/administered in first 7 days of admission
  SELECT
    ia.subject_id,
    ia.hadm_id,
    -- Use COALESCE to combine drugs from both tables
    LOWER(COALESCE(pr.drug, em.medication)) AS drug,
    COALESCE(pr.route, ed.route) AS route,
    CASE
      WHEN LOWER(COALESCE(pr.drug, em.medication)) IN (
        'warfarin','heparin','insulin','digoxin','amiodarone','lidocaine','epinephrine','norepinephrine','vasopressin',
        'morphine','fentanyl','midazolam','propofol','dopamine','dobutamine','nitroglycerin','clopidogrel','aspirin',
        'enoxaparin','hydromorphone','metoprolol','diltiazem','verapamil','atenolol','sotalol','quinidine','procainamide','magnesium sulfate'
      ) THEN 1 ELSE 0
    END AS is_high_risk
  FROM index_admissions ia
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON ia.hadm_id = pr.hadm_id
    AND pr.starttime >= ia.admittime
    AND pr.starttime < DATETIME_ADD(ia.admittime, INTERVAL 7 DAY)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` em
    ON ia.hadm_id = em.hadm_id
    AND em.charttime >= ia.admittime
    AND em.charttime < DATETIME_ADD(ia.admittime, INTERVAL 7 DAY)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
    ON em.emar_id = ed.emar_id AND em.emar_seq = ed.emar_seq
),
complexity_scores AS (
  -- Aggregate medication complexity per admission
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT drug) AS unique_drugs,
    COUNT(DISTINCT route) AS unique_routes,
    COUNT(DISTINCT CASE WHEN is_high_risk = 1 THEN drug END) AS high_risk_drugs,
    COUNT(*) AS med_events,
    -- Score formula
    COUNT(DISTINCT drug) + 2 * COUNT(DISTINCT CASE WHEN is_high_risk = 1 THEN drug END) + COUNT(DISTINCT route) AS complexity_score
  FROM meds_7d
  WHERE drug IS NOT NULL
  GROUP BY subject_id, hadm_id
),
admission_scores AS (
  -- Merge scores with index admissions, fill missing scores with zero
  SELECT
    ia.subject_id,
    ia.hadm_id,
    ia.admittime,
    ia.dischtime,
    ia.hospital_expire_flag,
    ia.anchor_age,
    ia.gender,
    COALESCE(cs.complexity_score, 0) AS complexity_score,
    COALESCE(cs.unique_drugs, 0) AS unique_drugs,
    COALESCE(cs.high_risk_drugs, 0) AS high_risk_drugs,
    COALESCE(cs.unique_routes, 0) AS unique_routes,
    DATETIME_DIFF(ia.dischtime, ia.admittime, HOUR)/24.0 AS los_days
  FROM index_admissions ia
  LEFT JOIN complexity_scores cs
    ON ia.subject_id = cs.subject_id AND ia.hadm_id = cs.hadm_id
),
score_tertiles AS (
  -- Compute tertile cutoffs
  SELECT
    APPROX_QUANTILES(complexity_score, 3) AS tertile_cutoffs
  FROM admission_scores
),
scored_admissions AS (
  -- Assign each admission to a tertile
  SELECT
    a.*,
    CASE
      WHEN a.complexity_score <= t.tertile_cutoffs[SAFE_OFFSET(0)] THEN 1
      WHEN a.complexity_score <= t.tertile_cutoffs[SAFE_OFFSET(1)] THEN 2
      ELSE 3
    END AS tertile
  FROM admission_scores a
  CROSS JOIN score_tertiles t
),
readmissions AS (
  -- For each index admission, check for readmission within 30 days
  SELECT
    sa.subject_id,
    sa.hadm_id,
    sa.dischtime,  -- <-- Added to GROUP BY
    MIN(next_adm.admittime) AS next_admittime,
    CASE
      WHEN MIN(next_adm.admittime) IS NOT NULL
           AND DATETIME_DIFF(MIN(next_adm.admittime), sa.dischtime, DAY) <= 30
      THEN 1 ELSE 0
    END AS readmit_30d
  FROM scored_admissions sa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` next_adm
    ON sa.subject_id = next_adm.subject_id
    AND next_adm.admittime > sa.dischtime
    AND DATETIME_DIFF(next_adm.admittime, sa.dischtime, DAY) <= 30
  GROUP BY sa.subject_id, sa.hadm_id, sa.dischtime  -- <-- FIXED
),
final AS (
  -- Merge readmission info
  SELECT
    sa.*,
    r.readmit_30d
  FROM scored_admissions sa
  LEFT JOIN readmissions r
    ON sa.subject_id = r.subject_id AND sa.hadm_id = r.hadm_id
)
SELECT
  tertile,
  COUNT(*) AS admission_count,
  MIN(complexity_score) AS score_min,
  MAX(complexity_score) AS score_max,
  ROUND(AVG(los_days),2) AS mean_los_days,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS in_hospital_mortality_pct,
  ROUND(100.0 * SUM(CASE WHEN readmit_30d = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS readmission_30d_pct
FROM final
GROUP BY tertile
ORDER BY tertile;