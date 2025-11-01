WITH admissions_with_age_gender AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.anchor_age BETWEEN 84 AND 94
    AND p.gender = 'F'
),

aki_admissions AS (
  SELECT DISTINCT
    a.hadm_id
  FROM admissions_with_age_gender a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE (
    (d.icd_version = 9 AND dd.icd_code LIKE '584%') OR
    (d.icd_version = 10 AND dd.icd_code LIKE 'N17%')
  )
),

medication_complexity AS (
  SELECT
    p.hadm_id,
    COUNT(DISTINCT p.drug) AS med_count
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN aki_admissions aki ON p.hadm_id = aki.hadm_id
  WHERE p.drug IS NOT NULL
  GROUP BY p.hadm_id
),

admissions_with_complexity AS (
  SELECT
    a.*,
    COALESCE(m.med_count, 0) AS med_count,
    NTILE(5) OVER (ORDER BY COALESCE(m.med_count, 0)) AS med_quintile
  FROM admissions_with_age_gender a
  JOIN aki_admissions aki ON a.hadm_id = aki.hadm_id
  LEFT JOIN medication_complexity m ON a.hadm_id = m.hadm_id
),

readmissions AS (
  SELECT
    a1.hadm_id,
    CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmit_30
  FROM admissions_with_complexity a1
  LEFT JOIN admissions_with_complexity a2
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.dischtime
    AND DATETIME_DIFF(a2.admittime, a1.dischtime, DAY) <= 30
  QUALIFY ROW_NUMBER() OVER (PARTITION BY a1.hadm_id ORDER BY a2.admittime) = 1
),

coadministered_drugs AS (
  SELECT
    p1.hadm_id,
    COUNT(*) AS anticoag_opioid_count
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p1
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p2
    ON p1.hadm_id = p2.hadm_id AND p1.subject_id = p2.subject_id
  WHERE
    (
      REGEXP_CONTAINS(LOWER(p1.drug), r'heparin|warfarin|rivaroxaban|apixaban|enoxaparin') OR
      LOWER(p1.drug) IN ('heparin', 'warfarin', 'rivaroxaban', 'apixaban', 'enoxaparin')
    )
    AND
    (
      REGEXP_CONTAINS(LOWER(p2.drug), r'morphine|fentanyl|hydromorphone|oxycodone') OR
      LOWER(p2.drug) IN ('morphine', 'fentanyl', 'hydromorphone', 'oxycodone')
    )
  GROUP BY p1.hadm_id
)

SELECT
  ac.med_quintile,
  AVG(ac.los) AS avg_los,
  AVG(ac.hospital_expire_flag) * 100 AS inpatient_mortality_pct,
  AVG(COALESCE(r.readmit_30, 0)) * 100 AS readmit_30_pct,
  SUM(COALESCE(cd.anticoag_opioid_count, 0)) AS anticoag_opioid_coadmin_count
FROM admissions_with_complexity ac
LEFT JOIN readmissions r ON ac.hadm_id = r.hadm_id
LEFT JOIN coadministered_drugs cd ON ac.hadm_id = cd.hadm_id
GROUP BY ac.med_quintile
ORDER BY ac.med_quintile;