WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    a.hadm_id = i.hadm_id
  JOIN
    (
      SELECT hadm_id, MIN(intime) AS first_intime
      FROM `physionet-data.mimiciv_3_1_icu.icustays`
      GROUP BY hadm_id
    ) first_icu
  ON
    i.hadm_id = first_icu.hadm_id AND i.intime = first_icu.first_intime
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 36 AND 46
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE
        LOWER(dd.long_title) LIKE '%diabetes%'
    )
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE
        LOWER(dd.long_title) LIKE '%heart failure%'
    )
),

drug_flags AS (
  SELECT
    c.hadm_id,
    c.intime,
    c.outtime,
    pr.starttime,
    CASE
      WHEN LOWER(pr.drug) LIKE '%insulin%' OR LOWER(pr.drug) LIKE '%metformin%' OR LOWER(pr.drug) LIKE '%glipizide%' THEN 1
      ELSE 0
    END AS is_antidiabetic,
    CASE
      WHEN LOWER(pr.drug) LIKE '%furosemide%' OR LOWER(pr.drug) LIKE '%digoxin%' OR LOWER(pr.drug) LIKE '%carvedilol%' THEN 1
      ELSE 0
    END AS is_cardiac
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON
    c.hadm_id = pr.hadm_id
),

time_window_flags AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN starttime >= intime AND starttime <= DATETIME_ADD(intime, INTERVAL 48 HOUR) THEN is_antidiabetic ELSE 0 END) AS anti_48h,
    MAX(CASE WHEN starttime >= intime AND starttime <= DATETIME_ADD(intime, INTERVAL 48 HOUR) THEN is_cardiac ELSE 0 END) AS cardio_48h,
    MAX(CASE WHEN starttime >= DATETIME_SUB(outtime, INTERVAL 12 HOUR) AND starttime <= outtime THEN is_antidiabetic ELSE 0 END) AS anti_last12h,
    MAX(CASE WHEN starttime >= DATETIME_SUB(outtime, INTERVAL 12 HOUR) AND starttime <= outtime THEN is_cardiac ELSE 0 END) AS cardio_last12h
  FROM
    drug_flags
  GROUP BY
    hadm_id, intime, outtime
),

prevalence AS (
  SELECT
    'Antidiabetic' AS drug_class,
    100 * AVG(anti_48h) AS prevalence_48h,
    100 * AVG(anti_last12h) AS prevalence_last12h,
    100 * (AVG(anti_48h) - AVG(anti_last12h)) AS diff_pp
  FROM
    time_window_flags

  UNION ALL

  SELECT
    'Cardiac' AS drug_class,
    100 * AVG(cardio_48h) AS prevalence_48h,
    100 * AVG(cardio_last12h) AS prevalence_last12h,
    100 * (AVG(cardio_48h) - AVG(cardio_last12h)) AS diff_pp
  FROM
    time_window_flags
)

SELECT * FROM prevalence
ORDER BY drug_class;