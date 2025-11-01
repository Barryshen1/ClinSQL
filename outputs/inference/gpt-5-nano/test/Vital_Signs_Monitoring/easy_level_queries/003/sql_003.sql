WITH hr_per_stay AS (
  SELECT
    icu.stay_id,
    AVG(ce.valuenum) AS mean_hr
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON icu.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.hadm_id = ce.hadm_id AND icu.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE
    pat.gender = 'M'
    AND LOWER(di.label) LIKE '%heart rate%'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime IS NOT NULL
    -- Age at admission: anchor_age + (admission_year - anchor_year)
    AND (CAST(pat.anchor_age AS INT64) +
         (EXTRACT(YEAR FROM adm.admittime) - CAST(pat.anchor_year AS INT64)))
        BETWEEN 40 AND 50
  GROUP BY icu.stay_id
)

SELECT
  AVG(mean_hr) AS median_per_stay_mean_hr
FROM (
  SELECT
    mean_hr,
    ROW_NUMBER() OVER (ORDER BY mean_hr) AS rn,
    COUNT(*) OVER () AS cnt
  FROM hr_per_stay
) t
WHERE
  (MOD(cnt, 2) = 1 AND rn = DIV(cnt + 1, 2))
  OR
  (MOD(cnt, 2) = 0 AND rn IN (DIV(cnt, 2), DIV(cnt, 2) + 1));