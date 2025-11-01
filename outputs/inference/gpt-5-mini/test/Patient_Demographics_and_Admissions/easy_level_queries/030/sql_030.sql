WITH first_admissions AS (
  -- First hospital admission per patient (earliest admittime)
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- fractional days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.dischtime IS NOT NULL
    -- ensure this is the earliest admission for the subject
    AND a.admittime = (
      SELECT MIN(a2.admittime)
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = a.subject_id
    )
),

anticoag_admissions AS (
  -- Admissions with any anticoagulant recorded in prescriptions, pharmacy, or emar
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE drug IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(drug),
        r'warfarin|coumadin|heparin|enoxaparin|dalteparin|fondaparinux|apixaban|rivaroxaban|dabigatran|edoxaban|bivalirudin|argatroban|tinzaparin'
    )

  UNION DISTINCT

  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE medication IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(medication),
        r'warfarin|coumadin|heparin|enoxaparin|dalteparin|fondaparinux|apixaban|rivaroxaban|dabigatran|edoxaban|bivalirudin|argatroban|tinzaparin'
    )

  UNION DISTINCT

  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.emar`
  WHERE medication IS NOT NULL
    AND REGEXP_CONTAINS(LOWER(medication),
        r'warfarin|coumadin|heparin|enoxaparin|dalteparin|fondaparinux|apixaban|rivaroxaban|dabigatran|edoxaban|bivalirudin|argatroban|tinzaparin'
    )
)

SELECT
  COUNT(1) AS n_patients,
  STDDEV_SAMP(f.los_days) AS sd_los_days
FROM first_admissions f
JOIN anticoag_admissions m
  ON f.subject_id = m.subject_id
  AND f.hadm_id = m.hadm_id;