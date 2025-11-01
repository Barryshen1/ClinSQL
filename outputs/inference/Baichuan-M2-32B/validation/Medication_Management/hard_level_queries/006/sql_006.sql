WITH eligible_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON a.hadm_id = proc.hadm_id
  WHERE 
    p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 37 AND 47
),
icu_stays AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    i.stay_id,
    i.intime,
    i.los
  FROM eligible_admissions e
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON e.hadm_id = i.hadm_id
),
meds AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.los,  -- Added to propagate ICU length of stay
    COUNT(DISTINCT COALESCE(p.formulary_drug_cd, p.drug)) AS medication_count
  FROM icu_stays i
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON i.subject_id = p.subject_id
    AND i.hadm_id = p.hadm_id
    AND p.starttime >= i.intime
    AND p.starttime < i.intime + INTERVAL 72 HOUR
  GROUP BY i.subject_id, i.hadm_id, i.stay_id, i.intime, i.los  -- Added i.los to GROUP BY
),
quintiles AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    m.stay_id,
    m.medication_count,
    m.los,  -- Now available from meds
    NTILE(5) OVER (ORDER BY m.medication_count) AS quintile
  FROM meds m
),
adm_outcomes AS (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag,
    CASE 
      WHEN MIN(a2.admittime) IS NOT NULL 
        AND MIN(a2.admittime) <= a.dischtime + INTERVAL 30 DAY 
      THEN 1 
      ELSE 0 
    END AS readmitted
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON a.subject_id = a2.subject_id
    AND a2.admittime > a.dischtime
    AND a2.admittime <= a.dischtime + INTERVAL 30 DAY
  WHERE a.hadm_id IN (SELECT hadm_id FROM quintiles)
  GROUP BY a.hadm_id, a.hospital_expire_flag
)
SELECT
  q.quintile,
  AVG(q.los) AS avg_los,
  100 * COUNT(DISTINCT CASE WHEN o.hospital_expire_flag = 1 THEN q.hadm_id END) / COUNT(DISTINCT q.hadm_id) AS mortality_rate_percent,
  100 * COUNT(DISTINCT CASE WHEN o.readmitted = 1 THEN q.hadm_id END) / COUNT(DISTINCT q.hadm_id) AS readmission_rate_percent
FROM quintiles q
INNER JOIN adm_outcomes o
  ON q.hadm_id = o.hadm_id
GROUP BY q.quintile
ORDER BY q.quintile;