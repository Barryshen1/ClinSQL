WITH first_sodium_by_stay AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    l.charttime AS first_charttime,
    l.valuenum AS first_sodium
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON l.subject_id = i.subject_id
   AND l.hadm_id = i.hadm_id
   AND l.charttime BETWEEN i.intime AND i.outtime
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS di
    ON di.itemid = l.itemid
  WHERE LOWER(di.label) LIKE '%sodium%'
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY i.subject_id, i.hadm_id, i.stay_id
    ORDER BY l.charttime
  ) = 1
),

cohort AS (
  -- index sodium values for male patients
  SELECT f.first_sodium
  FROM first_sodium_by_stay f
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = f.subject_id
  WHERE p.gender = 'M'
    AND f.first_sodium IS NOT NULL
)

SELECT
  (q)[OFFSET(24)] AS first_sodium_q1,
  (q)[OFFSET(74)] AS first_sodium_q3,
  (q)[OFFSET(74)] - (q)[OFFSET(24)] AS iqr
FROM (
  SELECT APPROX_QUANTILES(first_sodium, 100) AS q
  FROM cohort
);