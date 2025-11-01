WITH first_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      USING (subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
)
, dap_prescriptions AS (
  SELECT
    fa.subject_id,
    fa.hadm_id,
    -- flag for aspirin
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%aspirin%' THEN 1 ELSE 0 END) AS has_aspirin,
    -- flag for P2Y12 inhibitors
    MAX(CASE
          WHEN LOWER(pr.drug) LIKE '%clopidogrel%'
            OR LOWER(pr.drug) LIKE '%prasugrel%'
            OR LOWER(pr.drug) LIKE '%ticagrelor%'
          THEN 1
          ELSE 0
        END) AS has_p2y12
  FROM
    first_admissions AS fa
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
      ON fa.subject_id = pr.subject_id
      AND fa.hadm_id    = pr.hadm_id
      AND pr.starttime BETWEEN fa.admittime AND fa.dischtime
  WHERE
    fa.rn = 1
  GROUP BY
    fa.subject_id,
    fa.hadm_id
)
, dap_cohort AS (
  -- keep only admissions with both aspirin and a P2Y12 inhibitor
  SELECT
    d.subject_id,
    d.hadm_id
  FROM
    dap_prescriptions AS d
  WHERE
    d.has_aspirin = 1
    AND d.has_p2y12 = 1
)
SELECT
  -- standard deviation of the binary mortality indicator
  STDDEV_SAMP(CAST(fa.hospital_expire_flag AS INT64)) AS sd_in_hospital_mortality
FROM
  first_admissions AS fa
  JOIN dap_cohort AS dc
    USING (subject_id, hadm_id)
WHERE
  fa.rn = 1;