WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age AS age,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los AS icu_los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON ic.subject_id = p.subject_id
  WHERE
    p.gender = 'F' AND p.anchor_age BETWEEN 52 AND 62
), VitalSignInstability AS (
  SELECT
    p.subject_id,
    p.stay_id,
    p.intime,
    SUM(CASE
      WHEN ce.itemid IN (44, 51, 66, 78, 113, 114, 115, 128, 167, 207, 220189, 220190, 220191, 220192, 220193, 220194, 220195, 220196, 220197, 220198, 220199, 220200, 220201, 220202, 220203, 220204, 220205, 220206, 220207, 220208, 220209, 220210, 220211, 220212, 220213, 220214, 220215, 220216, 220217, 220218, 220219, 220220, 220221, 220222, 220223, 220224, 220225, 220226, 220227, 220228, 220229, 220230, 220231, 220232, 220233, 220234, 220235, 220236, 220237, 220238, 220239, 220240, 220241, 220242, 220243, 220244, 220245, 220246, 220247, 220248, 220249, 220250, 220251, 220252, 220253, 220254, 22;