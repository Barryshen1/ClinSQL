WITH PatientICUStay AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON ic.subject_id = p.subject_id
  WHERE
    p.gender = 'F' AND p.anchor_age BETWEEN 75 AND 85
),
Ventilation AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id,
    p.stay_id
  FROM PatientICUStay AS p
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON p.subject_id = ce.subject_id AND p.hadm_id = ce.hadm_id AND p.stay_id = ce.stay_id
  WHERE
    ce.itemid IN (50919, 50920, 50921, 50922, 50923, 50924, 50925, 50926, 50927, 50928, 50929, 50930, 50931, 50932, 50933, 50934, 50935, 50936, 50937, 50938, 50939, 50940, 50941, 50942, 50943, 50944, 50945, 50946, 50947, 50948, 50949, 50950, 50951, 50952, 50953, 50954, 50955, 50956, 50957, 50958, 50959, 50960, 50961, 50962, 50963, 50964, 50965, 50966, 50967, 50968, 50969, 50970, 50971, 50972, 50973, 50974, 50975, 50976, 50977, 50978, 50979, 50980, 50981, 50982, 50983, 50984, 50985, 50986, 50987, 5098;