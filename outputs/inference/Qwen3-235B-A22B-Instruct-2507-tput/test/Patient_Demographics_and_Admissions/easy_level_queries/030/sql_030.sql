WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN (
    SELECT
      subject_id,
      MIN(admittime) AS first_admittime
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions`
    GROUP BY
      subject_id
  ) first_adm
  ON a.subject_id = first_adm.subject_id AND a.admittime = first_adm.first_admittime
),
anticoagulant_drugs AS (
  SELECT DISTINCT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN
    first_admissions fa
  ON p.subject_id = fa.subject_id AND p.hadm_id = fa.hadm_id
  WHERE
    LOWER(drug) IN (
      'warfarin', 'heparin', 'enoxaparin', 'dalteparin', 'fondaparinux',
      'apixaban', 'rivaroxaban', 'edoxaban', 'dabigatran', 'bivalirudin',
      'argatroban', 'lepirudin'
    )
),
eligible_patients AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    anticoagulant_drugs a
  ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age >= 52
    AND p.anchor_age <= 62
)
SELECT
  ROUND(STDDEV(fa.los_days), 4) AS sd_first_admission_los_days
FROM
  first_admissions fa
INNER JOIN
  eligible_patients ep
ON fa.subject_id = ep.subject_id;