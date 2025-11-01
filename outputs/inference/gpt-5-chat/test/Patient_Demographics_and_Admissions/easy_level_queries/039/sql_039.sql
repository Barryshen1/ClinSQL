WITH first_icu AS (
  SELECT
    p.subject_id,
    i.hadm_id,
    i.stay_id,
    i.los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    -- choose first ICU stay per patient
    AND i.intime = (
      SELECT MIN(intime)
      FROM `physionet-data.mimiciv_3_1_icu.icustays`
      WHERE subject_id = p.subject_id
    )
)
SELECT
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS los_25th_percentile_days
FROM first_icu;