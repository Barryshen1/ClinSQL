WITH surgical_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.services s ON a.hadm_id = s.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
    AND s.curr_service IN ('SURG', 'CSURG', 'TSURG', 'VSURG', 'NSURG', 'PSURG', 'ORTHO', 'NEURO', 'CARD', 'THOR', 'URO', 'GYNE', 'ENT', 'OPHTH', 'DENT', 'PLAS', 'TRAU')
),

medication_complexity AS (
  SELECT
    sa.hadm_id,
    COUNT(DISTINCT pr.drug) AS unique_drugs,
    COUNT(DISTINCT CASE
      WHEN LOWER(pr.drug) LIKE '%heparin%'
        OR LOWER(pr.drug) LIKE '%warfarin%'
        OR LOWER(pr.drug) LIKE '%apixaban%'
        OR LOWER(pr.drug) LIKE '%rivaroxaban%'
        OR LOWER(pr.drug) LIKE '%dabigatran%'
        OR LOWER(pr.drug) LIKE '%edoxaban%'
        OR LOWER(pr.drug) LIKE '%enoxaparin%'
        OR LOWER(pr.drug) LIKE '%insulin%'
        OR LOWER(pr.drug) LIKE '%glargine%'
        OR LOWER(pr.drug) LIKE '%lispro%'
        OR LOWER(pr.drug) LIKE '%aspart%'
        OR LOWER(pr.drug) LIKE '%regular%'
        OR LOWER(pr.drug) LIKE '%norepinephrine%'
        OR LOWER(pr.drug) LIKE '%dopamine%'
        OR LOWER(pr.drug) LIKE '%epinephrine%'
        OR LOWER(pr.drug) LIKE '%phenylephrine%'
        OR LOWER(pr.drug) LIKE '%vasopressin%'
        OR LOWER(pr.drug) LIKE '%dobutamine%'
        OR LOWER(pr.drug) LIKE '%propofol%'
        OR LOWER(pr.drug) LIKE '%midazolam%'
        OR LOWER(pr.drug) LIKE '%dexmedetomidine%'
        OR LOWER(pr.drug) LIKE '%lorazepam%'
        OR LOWER(pr.drug) LIKE '%fentanyl%'
        OR LOWER(pr.drug) LIKE '%morphine%'
        OR LOWER(pr.drug) LIKE '%hydromorphone%'
        OR LOWER(pr.drug) LIKE '%oxycodone%'
        OR LOWER(pr.drug) LIKE '%codeine%'
        OR LOWER(pr.drug) LIKE '%amiodarone%'
        OR LOWER(pr.drug) LIKE '%digoxin%'
      THEN pr.drug
    END) AS high_risk_drugs
  FROM surgical_admissions sa
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.prescriptions pr ON sa.hadm_id = pr.hadm_id
    AND pr.starttime >= sa.admittime
    AND pr.starttime < TIMESTAMP_ADD(sa.admittime, INTERVAL 24 HOUR)
  GROUP BY sa.hadm_id
),

complexity_quartiles AS (
  SELECT
    sa.*,
    COALESCE(mc.unique_drugs, 0) AS unique_drugs,
    COALESCE(mc.high_risk_drugs, 0) AS high_risk_drugs,
    COALESCE(mc.unique_drugs, 0) + COALESCE(mc.high_risk_drugs, 0) AS medication_complexity_score,
    NTILE(4) OVER (ORDER BY COALESCE(mc.unique_drugs, 0) + COALESCE(mc.high_risk_drugs, 0)) AS quartile
  FROM surgical_admissions sa
  LEFT JOIN medication_complexity mc ON sa.hadm_id = mc.hadm_id
),

readmission_flag AS (
  SELECT
    a1.hadm_id,
    CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmission_30d
  FROM complexity_quartiles a1
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.admissions a2
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND a2.admittime <= TIMESTAMP_ADD(a1.dischtime, INTERVAL 30 DAY)
)

SELECT
  cq.quartile,
  COUNT(*) AS patient_count,
  AVG(TIMESTAMP_DIFF(cq.dischtime, cq.admittime, DAY)) AS avg_los_days,
  AVG(CAST(cq.hospital_expire_flag AS FLOAT64)) * 100 AS in_hospital_mortality_pct,
  AVG(CAST(r.readmission_30d AS FLOAT64)) * 100 AS thirty_day_readmission_pct
FROM complexity_quartiles cq
JOIN readmission_flag r ON cq.hadm_id = r.hadm_id
GROUP BY cq.quartile
ORDER BY cq.quartile;