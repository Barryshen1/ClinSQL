WITH spo2_by_stay AS (
  SELECT
    i.stay_id,
    i.subject_id,
    AVG(ce.valuenum) AS spo2_mean
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = i.subject_id
   AND ce.hadm_id = i.hadm_id
   AND ce.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE (
          di.label LIKE '%SpO2%'
          OR di.label LIKE '%Oxygen saturation%'
        )
    AND ce.valuenum IS NOT NULL
    AND p.gender = 'F'
    -- age at admission: anchorAge + (year(admittime) - anchor_year)
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 38 AND 48
  GROUP BY i.stay_id, i.subject_id
)

SELECT
  COUNT(*) AS n_stays_in_cohort,
  SAFE_DIVIDE(
    SUM(CASE WHEN spo2_mean <= 92 THEN 1 ELSE 0 END),
    COUNT(*)
  ) * 100 AS percentile_92
FROM spo2_by_stay;