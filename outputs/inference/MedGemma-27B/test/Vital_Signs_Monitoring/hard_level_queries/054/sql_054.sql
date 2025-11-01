WITH
  -- Define the composite instability score
  instability_score AS (
    SELECT
      ic.subject_id,
      ic.hadm_id,
      ic.stay_id,
      ic.charttime,
      CASE
        WHEN ce.value < 65 THEN 1
        ELSE 0
      END AS map_burden,
      CASE
        WHEN ce_hr.value > 100 THEN 1
        ELSE 0
      END AS hr_burden,
      (
        CASE
          WHEN ce.value < 65 THEN 1
          ELSE 0
        END + CASE
          WHEN ce_hr.value > 100 THEN 1
          ELSE 0
        END
      ) AS composite_burden
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` AS ic
      LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
        ON ic.stay_id = ce.stay_id AND ce.itemid = 455 -- MAP
      LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce_hr
        ON ic.stay_id = ce_hr.stay_id AND ce_hr.itemid = 3031 -- HR
    WHERE
      ce.value IS NOT NULL AND ce_hr.value IS NOT NULL
  ),
  -- Filter patients based on age and gender
  filtered_patients AS (
    SELECT
      p.subject_id,
      p.gender,
      p.anchor_age
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    WHERE
      p.gender = 'M' AND p.anchor_age BETWEEN 82 AND 92
  ),
  -- Filter patients based on diagnosis of acute respiratory failure
  arf_patients AS (
    SELECT
      d.subject_id,
      d.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
    WHERE
      di.long_title LIKE '%respiratory failure%'
      OR di.long_title LIKE '%respiratory insufficiency%'
      OR di.long_title LIKE '%respiratory arrest%'
  ),
  -- Combine patient filters
  target_patients AS (
    SELECT
      fp.subject_id,
      fp.hadm_id
    FROM
      filtered_patients AS fp
      JOIN arf_patients AS arf
        ON fp.subject_id = arf.subject_id
  ),
  -- Calculate instability score for target patients within the first 72 hours
  instability_72h AS (
    SELECT
      tp.subject_id,
      tp.hadm_id,
      iscore.charttime,
      iscore.composite_burden
    FROM
      target_patients AS tp
      JOIN instability_score AS iscore
        ON tp.subject_id;